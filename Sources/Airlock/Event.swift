//
//  File.swift
//  
//
//  Created by Liam Fitzgerald on 1/12/21.
//

import Foundation
import Combine
import EventSource

enum AirlockGift: Decodable {
    case diff(Data) //  Ideally we would have the diff mark statically, but we don't
    case ack(tang: String?)
    case quit
}

struct AirlockSign: Decodable {
    var id: Int;
    var gift: AirlockGift
}



enum AirlockTask {
    case watch(app: String, path: String)
    case poke(app: String, cage: OCage)
    case ack(Int)
    
    func toNote(_ id: Int) -> AirlockNote {
        return AirlockNote(task: self, id: id);
    }
}

struct AirlockNote {
    var task: AirlockTask;
    var id: Int;
}

protocol OCage: Encodable {
    static var mark: String { get };
}

protocol ICage: Decodable {
    static var mark: String { get };
}

enum AirlockError: Error {
    case encoding
    case network
    case nack(tang: String)
}




protocol Cage: OCage, ICage {}

class AirlockChannel {
    private var url: String = "http://localhost"
    var channelId: String = "test"
    private var txEventId: Int = 0
    private var rxEventId: Int = 0
    private var decoder = JSONDecoder()
    private var connected = false
    private var eventSource: EventSource?
    
    func poke(app: String, cage: OCage) -> AnyPublisher<(), AirlockError> {
        let task: AirlockTask = .poke(app: app, cage: cage);
        let id = self.getEventId();
        
        return send(id: id, task: task).flatMap({ _ in self.waitForAck(id: id) }).eraseToAnyPublisher();
    }
    
    func watchFor<T>(app: String, path: String, type: T.Type) -> AnyPublisher<T, AirlockError> where T: Decodable {
        let task: AirlockTask = .watch(app: app, path: path);
        let id = getEventId();
        
        return send(id: id, task: task).flatMap({ _ in self.waitForAck(id: id) }).flatMap({
            _ in
            return self.stream.compactMap({ sign -> T? in
                if(sign.id != id) {
                    return nil;
                }
                switch sign.gift {
                case .diff(let dat):
                    guard let fact = try? self.decoder.decode(type, from: dat) else {
                        return nil;
                    }
                    return fact;
                default:
                    return nil;
                }
            })
        })
            .eraseToAnyPublisher();
    }
    
    private func connectIfDisconnected() -> AnyPublisher<(), AirlockError> {
        if(self.connected) {
            return Just(()).mapError({ _ in AirlockError.network }).eraseToAnyPublisher();
        }
        self.connected = true;
        
        let ev = EventSource(url: self.channelUrl)
        ev.connect();
        ev.onMessage({ (idStr, event, dataStr) in
            if(dataStr == nil) {
                return
            }
            guard let id = Int(idStr ?? "") else {
                return
            }
            guard let data = try? JSONDecoder().decode(AirlockSign.self, from: dataStr!.data(using: .utf8)!) else {
                return
            }
            self.rxEventId = id;
            
            self.stream.send(data)
            
        });
        
        let connecting = PassthroughSubject<(), AirlockError>();
        
        ev.onOpen({
            connecting.send(());
        })
        
        return connecting.first().eraseToAnyPublisher();
        
        
//        return Just(()).eraseToAnyPublisher();
        
        
    }
    
    private func waitForAck(id: Int) -> AnyPublisher<(), AirlockError> {
        return stream.filter({ $0.id == id }).first().map({ _ in () }).eraseToAnyPublisher();
    }
    
    private func send(id: Int, task: AirlockTask) -> AnyPublisher<(), AirlockError> {
        let note = task.toNote(id);
        var req = URLRequest(url: channelUrl);
        req.httpMethod = "PUT";
        req.setValue("Application/json", forHTTPHeaderField: "Content-Type");
        guard let body = try? JSONSerialization.data(withJSONObject: [note], options: []) else {
            self.txEventId -= 1;
            return Fail<(), AirlockError>(error: AirlockError.encoding).eraseToAnyPublisher();
        }
        
        req.httpBody = body;
        return URLSession.shared.dataTaskPublisher(for: req).mapError({ err in
            return AirlockError.network
        }).map({ _ in () }).eraseToAnyPublisher();
    }
    
    private func getEventId() -> Int {
        txEventId += 1;
        return txEventId;
    }
    
    private var channelUrl: URL {
        return URL(string: "\(url)/~/channel/\(channelId)")!;
    }
    
    private var stream = PassthroughSubject<AirlockSign, AirlockError>();
    
}

struct LoginBody {
    var code: String;
}

class Airlock {
    var ship: String;
    var code: String;
    var url: URL;
    
    var channels: [String: AirlockChannel] = [:];
    
    func login() -> AnyPublisher<(), AirlockError> {
        var req = URLRequest(url: url.appendingPathComponent("/~/login"));
        req.httpMethod = "POST";
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type");
        let body = "code=\(code)".data(using: .utf8)!;
        req.httpBody = body;
        
        return URLSession.shared.dataTaskPublisher(for: req).map({ res in
            print(res);
            return () }).mapError({ _ in AirlockError.network }).eraseToAnyPublisher();
    }
    
    func newChannel() -> AirlockChannel {
        let channel = AirlockChannel();
        channels[channel.channelId] = channel;
        return channel;
    }
    
    init?(ship: String, code: String, url: String) {
        self.ship = ship;
        self.code = code;
        guard let u = URL(string: url) else {
            return nil;
        }
        self.url = u;
    }
}

extension Int: Decodable {
    

}

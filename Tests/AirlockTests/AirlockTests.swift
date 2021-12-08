import XCTest
import Combine
@testable import Airlock

final class AirlockTests: XCTestCase {
    var airlock: AirlockClient?;
    var cancellables: Set<AnyCancellable> = [];
    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        let expectation = self.expectation(description: "Login")
        airlock = AirlockClient(ship: "~zod", code: "lidlut-tabwed-pillex-ridrup", url: "http://localhost");
        if(airlock == nil) {
            XCTFail();
            return;
        }
        
        let _ = airlock!.login().sink(receiveCompletion: { completion in
            switch completion {
            case .finished:
                expectation.fulfill();
            case .failure(let err):
                print(err);
                XCTFail();
            }
        }) { res in
            print("logged in");
        }.store(in: &cancellables);
        waitForExpectations(timeout: 10);
    }
    
    func testWatch() {
        let expectation = self.expectation(description: "Test");
        if(airlock == nil) {
            XCTFail();
            return;
        }
        
        let channel = airlock!.newChannel();
        
        let _ = channel.watchFor(app: "graph-push-hook", path: "/version", type: Int.self   ).sink(receiveCompletion: {
            _ in
            print("a");
            
        }, receiveValue: {
             val in
            print(val);
            expectation.fulfill()
        }).store(in: &cancellables)
        
        
        waitForExpectations(timeout: 10);
    }
}

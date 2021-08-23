import ArgumentParser
import Foundation
import AppKit

struct Jab: ParsableCommand {
    static let dateFormat = "yyyy-MM-dd HH:mm"
    
    @Option(name: [.customShort("P"), .long], help: "Practice ID.")
    var practiceId: Int

    @Option(name: [.customShort("d"), .long], help: "Notify about appointments before given date, format: \(dateFormat)")
    var beforeDate: String?
    
    @Option(name: .shortAndLong, help: "Period of checks in minutes.")
    var period: Int = 15

    mutating func run() throws {
        let beforeDate: Date?
        if let beforeDateString = self.beforeDate {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = Self.dateFormat
            guard let beforeDateParsed = dateFormatter.date(from: beforeDateString) else {
                fatalError("Incorrect date format. Expected format: \(Self.dateFormat)")
            }
            beforeDate = beforeDateParsed
        } else {
            beforeDate = nil
        }
        
        let timeInterval = TimeInterval(period * 60)
        let practiceId = self.practiceId
        let timer = Timer(timeInterval: timeInterval, repeats: true) { _ in
            var request = URLRequest(url: URL(string: "https://api.healthengine.com.au/graphql")!)
            request.httpMethod = "POST"
            let dataBody = """
{"operationName":"FilteredAppointmentsForPractice","variables":{"practiceId":"\(practiceId)","display":"PLATFORM","from":"2021-08-21","numDays":4,"first":50,"specialty":"COVID-19 Vaccinations","typeFilter":{"patientType":"NEW","appointmentType":"Pfizer (First Dose)"},"test":false},"extensions":{},"query":"query FilteredAppointmentsForPractice($practiceId: ID!, $display: DisplayAppointment, $from: Date, $specialty: String!, $typeFilter: AppointmentTypeFilter, $first: Int, $numDays: Int, $after: String, $perDay: Int, $test: Boolean!) { practice(id: $practiceId) {id,appointments(search: {display: $display, specialty: [$specialty], date: {from: $from}, test: $test}, typeFilter: $typeFilter, after: $after, first: $first, perDay: $perDay, numDays: $numDays) { appointments {id, time, date, __typename}, totalCount, pageInfo { hasNextPage, startCursor, endCursor, __typename }, __typename}, __typename}}"}
""".data(using: .utf8)!
            request.allHTTPHeaderFields = [
                "Content-Type": "application/json",
                "Accept": "*/*",
                "Accept-Language": "en-au",
                "Host": "api.healthengine.com.au",
                "Origin": "https://healthengine.com.au",
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.2 Safari/605.1.15",
                "Referer": "https://healthengine.au/v2/appointment/book_widget/\(practiceId)/COVID-19%20Vaccinations?covaxEligibilityChecked=true",
                "Content-Length": "\(dataBody.count)",
                "Connection": "keep-alive",
                "X-Hannibal-Flags": "",
                "apollographql-client-version": "3f2aa4331fe5a8b519ec67ddab4041468e7749a6",
                "apollographql-client-name": "unicron-browser",
            ]
            request.httpBody = dataBody
            let dataTask = URLSession.shared.dataTask(with: request) { data, urlResponse, error in
                guard let data = data, let httpResponse = urlResponse as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    if let error = error {
                        Log.info("Error while fetching: \(error.localizedDescription)")
                    } else {
                        Log.info("Unknown error while fetching. Status code: \(String(describing: (urlResponse as? HTTPURLResponse)?.statusCode)). Data received: \(String(describing: String(data: data ?? Data(), encoding: .utf8)))")
                    }
                    return
                }
                do {
                    let payload = try JSONDecoder().decode(Payload.self, from: data)
                    guard let earliestDate = payload.data.practice.appointments.appointments.first else {
                        Log.info("No availabilty")
                        return
                    }
                    Log.info("Found earliest appointment: \(earliestDate.formattedDate)")
                    if earliestDate.date < beforeDate ?? Date.distantFuture {
                        Log.info("---------------------------------------------")
                        Log.info("            EARLIER DATE AVAILABLE")
                        Log.info("               \(earliestDate.formattedDate)")
                        Log.info("---------------------------------------------")
                        Log.info("")
                        Log.info("--> Book at: https://healthengine.com.au/v2/appointment/book_widget/\(practiceId)/COVID-19%20Vaccinations?covaxEligibilityChecked=true#appointment-selection")
                        Log.info("")
                        while true {
                            NSSound.beep()
                            Thread.sleep(forTimeInterval: 0.5)
                        }
                    }
                } catch {
                    Log.info("Error while parsing payload: \(error). Data received: \(String(describing: String(data: data, encoding: .utf8)))")
                }
            }
            dataTask.resume()
        }
        timer.fire()
        RunLoop.current.add(timer, forMode: .common)
        CFRunLoopRun()
    }
}

struct Log {
    static var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    static func info(_ message: String) {
        print("[\(dateFormatter.string(from: Date()))] \(message)")
    }
}

enum ParsingError: Error {
    case wrongDateTimeFormat
}

struct Payload: Decodable {
    let data: PayloadData
}
struct PayloadData: Decodable {
    let practice: Practice
}
struct Practice: Decodable {
    let appointments: PracticeAppointments
}
struct PracticeAppointments: Decodable {
    let appointments: [Appointment]
}
struct Appointment: Decodable {
    let formattedDate: String
    let date: Date
    
    enum CodingKeys: String, CodingKey {
        case time, date
    }
    
    static var dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df
    }()
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dateString = try container.decode(String.self, forKey: .date)
        let timeString = try container.decode(String.self, forKey: .time)
        formattedDate = "\(dateString) \(timeString)"
        guard let date = Self.dateFormatter.date(from: formattedDate) else {
            throw ParsingError.wrongDateTimeFormat
        }
        self.date = date
    }
}

Jab.main()

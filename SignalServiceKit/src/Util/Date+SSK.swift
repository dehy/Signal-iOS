//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

private let httpDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "E, dd MMM yyyy HH:mm:ss z"
    return formatter
}()

@available(iOSApplicationExtension 10.0, *)
private let internetDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = .withInternetDateTime
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}()

@available(iOSApplicationExtension 9.0, *)
private let iso8601DateFormatter: DateFormatter = {
        let enUSPOSIXLocale = Locale(identifier: "en_US_POSIX")
        let iso8601DateFormatter = DateFormatter()
        iso8601DateFormatter.locale = enUSPOSIXLocale
        iso8601DateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        iso8601DateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return iso8601DateFormatter
    }()

@objc
public extension NSDate {
    static func ows_parseFromHTTPDateString(_ string: String) -> NSDate? {
        return httpDateFormatter.date(from: string) as NSDate?
    }

    static func ows_parseFromISO8601String(_ string: String) -> NSDate? {
        if #available(iOSApplicationExtension 10.0, *) {
            return internetDateFormatter.date(from: string) as NSDate?
        } else {
            return iso8601DateFormatter.date(from: string) as NSDate?
        }
    }

    var ows_millisecondsSince1970: UInt64 {
        return NSDate.ows_millisecondsSince1970(for: self as Date)
    }
}

public extension Date {
    static func ows_parseFromHTTPDateString(_ string: String) -> Date? {
        return NSDate.ows_parseFromHTTPDateString(string) as Date?
    }

    static func ows_parseFromISO8601String(_ string: String) -> Date? {
        return NSDate.ows_parseFromISO8601String(string) as Date?
    }

    var ows_millisecondsSince1970: UInt64 {
        return (self as NSDate).ows_millisecondsSince1970
    }

    static func ows_millisecondTimestamp() -> UInt64 {
        return NSDate.ows_millisecondTimeStamp()
    }

    init(millisecondsSince1970: UInt64) {
        self = NSDate.ows_date(withMillisecondsSince1970: millisecondsSince1970) as Date
    }

    static var distantFutureForMillisecondTimestamp: Date {
        // Pick a value that's representable as both a UInt64 and an NSTimeInterval.
        let millis: UInt64 = 1 << 50
        let result = Date(millisecondsSince1970: millis)
        owsAssertDebug(millis == result.ows_millisecondsSince1970)
        return result
    }
}

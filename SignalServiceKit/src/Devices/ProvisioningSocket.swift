//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public protocol ProvisioningSocketDelegate: AnyObject {
    func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didReceiveDeviceId deviceID: String)
    func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didReceiveEnvelope envelope: ProvisioningProtoProvisionEnvelope)
    func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didError error: Error)
}

class TimerShim {
    private var timer: Timer?
    private let block: (Timer) -> Void

    private init(timeInterval interval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) {
        self.block = block
        timer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(timerDidFire), userInfo: nil, repeats: repeats)
    }

    class func scheduledTimer(withTimeInterval interval: TimeInterval, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
        return TimerShim(timeInterval: interval, repeats: repeats, block: block).timer!
    }

    @objc private func timerDidFire() {
        block(timer!)
    }
}

public class ProvisioningSocket {
    let socket: SSKWebSocket
    public weak var delegate: ProvisioningSocketDelegate?

    public init() {
        // TODO: Will this work with censorship circumvention?
        let serviceBaseURL = URL(string: TSConstants.textSecureWebSocketAPI)!
        let socketURL = URL(string: "/v1/websocket/provisioning/?agent=\(OWSUserAgent)",
                            relativeTo: serviceBaseURL)!

        let request = URLRequest(url: socketURL)
        socket = SSKWebSocketManager.buildSocket(request: request)
        socket.delegate = self
    }

    public var state: SSKWebSocketState {
        return socket.state
    }

    public func disconnect() {
        heartBeatTimer?.invalidate()
        heartBeatTimer = nil
        socket.disconnect()
    }

    var heartBeatTimer: Timer?
    public func connect() {
        if heartBeatTimer == nil {
            if #available(iOSApplicationExtension 10.0, *) {
                heartBeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    guard self.state == .open else { return }
                    
                    self.socket.writePing()
                }
            } else {
                // Fallback on earlier versions
                heartBeatTimer = TimerShim.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                    guard let self = self else { return }
                    guard self.state == .open else { return }
                    
                    self.socket.writePing()
                }
            }
        }
        socket.connect()
    }
}

extension ProvisioningSocket: SSKWebSocketDelegate {
    public func websocketDidConnect(socket: SSKWebSocket) {
        Logger.debug("")
    }

    public func websocketDidDisconnect(socket: SSKWebSocket, error: Error?) {
        if let error = error {
            delegate?.provisioningSocket(self, didError: error)
        } else {
            Logger.debug("disconnected without error.")
        }
    }

    public func websocket(_ socket: SSKWebSocket, didReceiveMessage message: WebSocketProtoWebSocketMessage) {
        guard let request = message.request else {
            owsFailDebug("unexpected message: \(message)")
            return
        }

        do {
            try handleRequest(request)
            try socket.sendResponse(for: request, status: 200, message: "OK")
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    private func handleRequest(_ request: WebSocketProtoWebSocketRequestMessage) throws {
        Logger.debug("message: \(request.verb) \(request.path)")
        switch (request.verb, request.path) {
        case ("PUT", "/v1/address"):
            guard let body = request.body else {
                throw OWSAssertionError("body was unexpectedly nil")
            }
            let uuidProto = try ProvisioningProtoProvisioningUuid(serializedData: body)
            delegate?.provisioningSocket(self, didReceiveDeviceId: uuidProto.uuid)
        case ("PUT", "/v1/message"):
            guard let body = request.body else {
                throw OWSAssertionError("body was unexpectedly nil")
            }
            let envelopeProto = try ProvisioningProtoProvisionEnvelope(serializedData: body)
            delegate?.provisioningSocket(self, didReceiveEnvelope: envelopeProto)
        default:
            throw OWSAssertionError("unexpected request: \(request)")
        }
    }
}

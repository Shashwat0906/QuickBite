import UIKit
#if canImport(Razorpay)
import Razorpay
#endif

/// Opens Razorpay's checkout UI for a server-created Razorpay order.
/// The signature returned by Razorpay is verified on *our server*, never here.
final class RazorpayCheckoutPresenter: NSObject {
    enum Result {
        case success(paymentId: String, orderId: String, signature: String)
        case cancelled
        case failed(String)
    }

    private var completion: ((Result) -> Void)?

    #if canImport(Razorpay)
    private var checkout: RazorpayCheckout?
    #endif

    func present(from viewController: UIViewController, payment: PaymentInfo, order: OrderDetail, user: User?, completion: @escaping (Result) -> Void) {
        self.completion = completion
        #if canImport(Razorpay)
        guard let key = payment.razorpayKeyId, let providerOrderId = payment.providerOrderId else {
            completion(.failed("Online payment isn't configured on the server."))
            return
        }
        checkout = RazorpayCheckout.initWithKey(key, andDelegateWithData: self)
        var options: [String: Any] = [
            "amount": payment.amountPaise,
            "currency": "INR",
            "order_id": providerOrderId,
            "name": "QuickBite",
            "description": "Order \(order.orderNumber)",
            "theme": ["color": "#E2572B"],
        ]
        if let user {
            var prefill: [String: String] = ["email": user.email]
            if let phone = user.phone { prefill["contact"] = phone }
            options["prefill"] = prefill
        }
        checkout?.open(options, displayController: viewController)
        #else
        completion(.failed("The Razorpay SDK isn't installed in this build. Run `pod install` (see README)."))
        #endif
    }

    fileprivate func finish(_ result: Result) {
        let completion = self.completion
        self.completion = nil
        DispatchQueue.main.async { completion?(result) }
    }
}

#if canImport(Razorpay)
extension RazorpayCheckoutPresenter: RazorpayPaymentCompletionProtocolWithData {
    func onPaymentError(_ code: Int32, description str: String, andData response: [AnyHashable: Any]?) {
        // Razorpay uses code 2 for "payment cancelled by user".
        finish(code == 2 ? .cancelled : .failed(str))
    }

    func onPaymentSuccess(_ payment_id: String, andData response: [AnyHashable: Any]?) {
        guard let orderId = response?["razorpay_order_id"] as? String,
              let signature = response?["razorpay_signature"] as? String else {
            finish(.failed("Payment succeeded but the response was incomplete. Please contact support."))
            return
        }
        finish(.success(paymentId: payment_id, orderId: orderId, signature: signature))
    }
}
#endif

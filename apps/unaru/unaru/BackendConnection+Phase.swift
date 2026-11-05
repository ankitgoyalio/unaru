//
//  BackendConnection+Phase.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

#if os(macOS)
    import Shared

    extension BackendConnection {
        /// Current connection state without cached identity.
        enum Phase: Equatable {
            /// The app is launching its embedded helper.
            case starting
            /// The embedded helper could not start or authorize the app.
            case startupFailed
            /// The app is making an authorized session-status request.
            case checking
            /// The helper requires Kite authentication.
            case signedOut
            /// An authorized browser attempt is pending.
            case loggingIn
            /// A temporary profile/status error can retry the same attempt.
            case loginUnavailable
            /// The browser attempt failed and can be started again.
            case loginFailed
            /// Exchange and profile retrieval succeeded.
            case signedIn(AccountProfile)
            /// Kite configuration needs repair.
            case backendError
            /// A temporary connection failure permits retry.
            case unavailable
            /// Saved authorization has not yet been durably removed.
            case logoutFailed
            /// Saved authorization awaits a successful provider validation.
            case sessionUnavailable
            /// Secure storage could not be read and remains available for retry.
            case storageUnavailable
        }
    }
#endif

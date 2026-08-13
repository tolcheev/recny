public struct MainRecorderLayoutPolicy: Equatable, Sendable {
    public let showsPermissionChecklist: Bool
    public let hasUpdateBanner: Bool
    public let status: RecordingStatus

    public init(
        showsPermissionChecklist: Bool,
        hasUpdateBanner: Bool,
        status: RecordingStatus = .idle
    ) {
        self.showsPermissionChecklist = showsPermissionChecklist
        self.hasUpdateBanner = hasUpdateBanner
        self.status = status
    }

    public var usesScrollableMainContent: Bool {
        showsPermissionChecklist || hasUpdateBanner
    }

    public var keepsFooterOutsideMainScroll: Bool {
        true
    }

    public var showsRecordingStatusCard: Bool {
        !showsPermissionChecklist || status != .idle
    }

    public var minimumWindowWidth: Double {
        520
    }

    public var idealWindowWidth: Double {
        560
    }

    public var maximumWindowWidth: Double {
        620
    }

    public var minimumWindowHeight: Double {
        showsPermissionChecklist ? 540 : 360
    }

    public var minimumScrollableContentHeight: Double {
        showsPermissionChecklist ? 300 : 220
    }

    public var mainContentSpacing: Double {
        showsPermissionChecklist ? 12 : 16
    }
}

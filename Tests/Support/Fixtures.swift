import Foundation

enum Fixtures {

    static let authStatusDisabled = """
    {"enabled":false,"setup_required":false,"authenticated":false,
     "username":null,"mode":"disabled","first_run":false}
    """

    static let authStatusEnabled = """
    {"enabled":true,"setup_required":false,"authenticated":false,
     "username":null,"mode":"enabled","first_run":false}
    """

    static let loginOK = #"{"status":"ok","username":"jeffre"}"#

    static let panelJSON = """
    {"id":"abc123def456","short_code":1,"name":"Living Room",
     "board_id":"11111111-2222-3333-4444-555555555555",
     "screen_diagonal_inches":65.0,"screen_aspect_w":16.0,"screen_aspect_h":9.0,
     "calibration_scale":1.0,"animations_enabled":false,"is_display":false,
     "backdrop":"wall","auto_dim":{"enabled":true,"start":"22:00","end":"07:00"},
     "created_at":"2026-09-01T12:00:00Z","updated_at":"2026-09-02T12:00:00Z",
     "device_type":"note_array","board_missing":false,"rows":12,"cols":30,
     "board_color":"black","code62_glyph":"heart"}
    """

    static var panelsList: String { #"{"panels":[\#(panelJSON)],"total":1}"# }

    /// A 2x3 frame: "HI" on the first row, a red tile on the second.
    static let frameJSON = """
    {"characters":[[8,9,0],[63,0,0]],"message":"HI",
     "rows":2,"cols":3,"updated_at":"2026-09-19T10:30:00Z"}
    """

    static let emptyFrameJSON = """
    {"characters":null,"message":null,"rows":12,"cols":30,"updated_at":null}
    """

    static let panelNotFound = #"{"detail":"Panel not found"}"#
}

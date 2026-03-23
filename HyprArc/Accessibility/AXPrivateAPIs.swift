import ApplicationServices

/// Private API used by AeroSpace, yabai, and Amethyst to bridge
/// AXUIElement ↔ CGWindowID. No public alternative exists.
/// Isolated here so it can be swapped if Apple ever removes it.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError

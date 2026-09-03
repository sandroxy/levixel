#!/usr/bin/env ruby
# frozen_string_literal: true

plugin_dir = File.expand_path("..", __dir__)
runtime_dir = File.join(
  plugin_dir,
  "adapters/uniapp/android/levixel-uniapp-runtime/src/main/java/com/sandrox/levixel/uniapp/runtime"
)

runtime_path = File.join(runtime_dir, "LevixelUniRuntime.java")
session_path = File.join(runtime_dir, "LevixelUniSession.java")
window_path = File.join(runtime_dir, "LevixelUniViewerWindow.java")

runtime = File.read(runtime_path)
session = File.read(session_path)
viewer_window = File.read(window_path)

abort("UniApp runtime must resolve the host content view without retaining the host decor") unless
  runtime.include?("activity.findViewById(android.R.id.content)") &&
  !runtime.include?("getDecorView()")

host_window_mutations = [
  "WindowCompat",
  "WindowInsetsControllerCompat",
  "setStatusBarColor",
  "setNavigationBarColor",
  "setSystemUiVisibility",
  "setDecorFitsSystemWindows",
  "FLAG_TRANSLUCENT_STATUS",
  "FLAG_TRANSLUCENT_NAVIGATION"
]

host_window_mutations.each do |mutation|
  abort("UniApp session must not mutate its host Window: #{mutation}") if
    runtime.include?(mutation) || session.include?(mutation)
end

required_session_contract = [
  "new LevixelUniViewerWindow(",
  "window.setContent(overlay)",
  "window.dismiss()"
]
required_session_contract.each do |contract|
  abort("UniApp session is missing isolated viewer Window behavior: #{contract}") unless
    session.include?(contract)
end

required_window_contract = [
  "new ViewerDialog(activity, listener::onBackRequested)",
  "WindowCompat.setDecorFitsSystemWindows(window, false)",
  "window.setStatusBarColor(Color.TRANSPARENT)",
  "window.setNavigationBarColor(Color.TRANSPARENT)",
  "setNavigationBarContrastEnforced(false)",
  "registerOnBackInvokedCallback(",
  "unregisterOnBackInvokedCallback(",
  "addOnAttachStateChangeListener("
]
required_window_contract.each do |contract|
  abort("Isolated UniApp viewer Window is missing: #{contract}") unless
    viewer_window.include?(contract)
end

abort("The isolated UniApp viewer must configure only its Dialog Window") if
  viewer_window.include?("activity.getWindow()")

puts "Verified UniApp Android viewer Window isolation."

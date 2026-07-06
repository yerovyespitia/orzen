source 'https://cdn.cocoapods.org'

install! 'cocoapods', deterministic_uuids: false
inhibit_all_warnings!

target 'Orzen' do
  platform :ios, '17.0'
  use_modular_headers!

  pod 'VLCKit', '4.0.0a19'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    end
  end
end

post_integrate do |installer|
  project = Xcodeproj::Project.open('Orzen.xcodeproj')
  target = project.targets.find { |candidate| candidate.name == 'Orzen' }
  next unless target

  target.shell_script_build_phases.each do |phase|
    next unless phase.name == '[CP] Embed Pods Frameworks'
    guard = "if [ \"${PLATFORM_NAME}\" = \"macosx\" ]; then\n  exit 0\nfi\n"
    phase.shell_script = guard + phase.shell_script unless phase.shell_script.start_with?(guard)
  end

  target.frameworks_build_phase.files.each do |build_file|
    next unless build_file.display_name == 'libPods-Orzen.a'
    build_file.platform_filter = 'ios' if build_file.respond_to?(:platform_filter=)
  end

  project.save
end

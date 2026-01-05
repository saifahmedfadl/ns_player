Pod::Spec.new do |s|
  s.name             = 'video_player_avfoundation'
  s.version          = '2.8.4'
  s.summary          = 'iOS implementation of video_player with custom buffer control.'
  s.description      = <<-DESC
iOS implementation of video_player with custom buffer control using AVPlayer.
                       DESC
  s.homepage         = 'https://github.com/Nurullah-Sadekin/ns_player'
  s.license          = { :type => 'BSD', :file => '../LICENSE' }
  s.author           = { 'NS Player' => 'info@nsplayer.com' }
  s.source           = { :http => 'https://github.com/Nurullah-Sadekin/ns_player' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end

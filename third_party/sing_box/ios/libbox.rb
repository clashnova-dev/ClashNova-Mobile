# Reviewed app-local native artifacts only. No upstream binary fallback.
require 'fileutils'
require 'digest'
require 'json'
module SingBoxLibbox
  FRAMEWORK = 'sing_box/Frameworks/Libbox.xcframework'.freeze
  module_function
  def ensure!(dir)
    dir = File.realpath(dir)
    reviewed = File.expand_path('../../../build/libbox/Libbox.xcframework', dir)
    raise 'Build reviewed libbox first: python3 scripts/prepare-libbox.py apple' unless File.file?(File.join(reviewed, 'Info.plist'))
    record = JSON.parse(File.read(File.join(File.dirname(reviewed), 'apple-build.json')))
    { 'go.mod' => 'goModSHA256', 'go.sum' => 'goSumSHA256', 'source.json' => 'sourceSHA256' }.each do |name, key|
      pin = File.expand_path('../../../native/' + name, dir)
      raise 'Native dependency pins changed; rerun python3 scripts/prepare-libbox.py apple' unless Digest::SHA256.file(pin).hexdigest == record[key]
    end
    destination = File.join(dir, FRAMEWORK)
    FileUtils.mkdir_p(File.dirname(destination))
    FileUtils.rm_rf(destination)
    FileUtils.cp_r(reviewed, destination)
    FRAMEWORK
  end
end

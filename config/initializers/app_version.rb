version = `git -C #{Rails.root} rev-parse --short HEAD 2>/dev/null`.strip
version = 'unknown' if version.blank?

version_file = Rails.root.join('public', 'version.json')
File.write(version_file, { version: version, deployed_at: Time.now.to_i }.to_json)

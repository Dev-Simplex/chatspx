require 'open3'

# Audio::WaveformExtractor
#
# Extracts a normalized peak array from an audio file using `ffmpeg`. The
# returned array contains PEAK_COUNT floats in the range 0.0..1.0, suitable
# for rendering a compact waveform visualization in the mobile client.
#
# Strategy:
#   1. Resample the audio to a low sample rate (mono / 8 kHz).
#   2. Use the `astats` filter with `asetnsamples` to bucket the signal into
#      PEAK_COUNT windows and emit one Peak_level per bucket (in dBFS).
#   3. Convert dBFS values back into the linear 0.0..1.0 range and clamp.
#
# Failure modes are handled defensively:
#   - Missing/unreadable file       => returns []
#   - ffmpeg binary missing         => returns [] + warn
#   - ffmpeg timeout (>30s)         => returns [] + warn (process is killed)
#   - ffmpeg non-zero exit          => returns [] + warn
#   - Corrupted/silent audio        => returns [] (no peaks parsed)
#
# The extractor never raises — callers should treat an empty array as
# "no waveform available" and skip persistence.
class Audio::WaveformExtractor
  PEAK_COUNT = 64
  TIMEOUT_SECONDS = 30
  TARGET_SAMPLE_RATE = 8_000

  # ffmpeg astats prints lines like:
  #   [Parsed_astats_2 @ 0x...] Peak level dB: -12.345678
  PEAK_LINE_REGEX = /Peak level dB:\s*(-?\d+(?:\.\d+)?|-?inf)/i

  def initialize(file_path)
    @file_path = file_path.to_s
  end

  # Returns Array<Float> of size PEAK_COUNT (normalized 0.0..1.0), or [] on error.
  def extract
    return [] if @file_path.blank? || !File.exist?(@file_path)

    stdout, stderr, status = run_ffmpeg
    return [] unless status&.success?

    peaks = parse_peaks(stdout, stderr)
    return [] if peaks.empty?

    normalize_to_peak_count(peaks)
  rescue Errno::ENOENT => e
    Rails.logger.warn("[Audio::WaveformExtractor] ffmpeg not available: #{e.message}")
    []
  rescue StandardError => e
    Rails.logger.warn("[Audio::WaveformExtractor] #{e.class}: #{e.message}")
    []
  end

  private

  def run_ffmpeg
    samples_per_window = TARGET_SAMPLE_RATE # 1 second windows at 8 kHz
    filter = "aresample=#{TARGET_SAMPLE_RATE},aformat=channel_layouts=mono," \
             "asetnsamples=n=#{samples_per_window}:p=0,astats=metadata=1:reset=1"

    cmd = [
      ffmpeg_path,
      '-nostdin', '-hide_banner', '-loglevel', 'info',
      '-i', @file_path,
      '-af', filter,
      '-f', 'null', '-'
    ]

    Timeout.timeout(TIMEOUT_SECONDS) do
      Open3.capture3(*cmd)
    end
  rescue Timeout::Error
    Rails.logger.warn("[Audio::WaveformExtractor] ffmpeg timed out after #{TIMEOUT_SECONDS}s for #{@file_path}")
    [nil, nil, nil]
  end

  # ffmpeg writes astats output to stderr. We scan both streams defensively.
  def parse_peaks(stdout, stderr)
    output = "#{stdout}\n#{stderr}"
    output.scan(PEAK_LINE_REGEX).map do |match|
      raw = match.first.to_s.downcase
      next 0.0 if raw == '-inf'

      db = raw.to_f
      # Convert dBFS -> linear amplitude: 10 ** (dB / 20)
      linear = 10.0**(db / 20.0)
      linear.clamp(0.0, 1.0)
    end
  end

  # ffmpeg with asetnsamples=8000 emits roughly one Peak level per second of
  # audio. Resample the resulting series to exactly PEAK_COUNT entries.
  def normalize_to_peak_count(peaks)
    return Array.new(PEAK_COUNT, 0.0) if peaks.empty?
    return peaks.first(PEAK_COUNT) + Array.new(PEAK_COUNT - peaks.size, 0.0) if peaks.size < PEAK_COUNT

    bucket_size = peaks.size.to_f / PEAK_COUNT
    Array.new(PEAK_COUNT) do |i|
      start_idx = (i * bucket_size).floor
      end_idx = [((i + 1) * bucket_size).floor, peaks.size].min
      end_idx = start_idx + 1 if end_idx <= start_idx

      slice = peaks[start_idx...end_idx]
      slice.max.to_f.clamp(0.0, 1.0)
    end
  end

  def ffmpeg_path
    ENV.fetch('FFMPEG_PATH', 'ffmpeg')
  end
end

require 'rails_helper'

RSpec.describe Audio::WaveformExtractor do
  let(:fixture_path) { Rails.root.join('spec/assets/sample.ogg').to_s }

  describe '#extract' do
    context 'when the file does not exist' do
      it 'returns an empty array' do
        result = described_class.new('/non/existent/audio.ogg').extract
        expect(result).to eq([])
      end
    end

    context 'when ffmpeg is not installed' do
      it 'logs a warning and returns []' do
        allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT, 'No such file or directory - ffmpeg')
        allow(File).to receive(:exist?).and_return(true)

        expect(Rails.logger).to receive(:warn).with(/ffmpeg not available/)
        expect(described_class.new(fixture_path).extract).to eq([])
      end
    end

    context 'when ffmpeg succeeds with parseable astats output' do
      it 'returns PEAK_COUNT normalized peaks in 0.0..1.0' do
        # Build a fake ffmpeg stderr containing 64 "Peak level dB" lines
        # ranging from -60 dB (quiet) to 0 dB (full scale).
        stderr_lines = (0...64).map do |i|
          db = -60.0 + (i * (60.0 / 63.0))
          "[Parsed_astats_2 @ 0x] Peak level dB: #{format('%.6f', db)}\n"
        end
        status = instance_double(Process::Status, success?: true)
        allow(Open3).to receive(:capture3).and_return(['', stderr_lines.join, status])
        allow(File).to receive(:exist?).and_return(true)

        peaks = described_class.new(fixture_path).extract

        expect(peaks).to be_an(Array)
        expect(peaks.size).to eq(described_class::PEAK_COUNT)
        expect(peaks).to all(be_between(0.0, 1.0))
        # First bucket comes from a -60 dB sample (~0.001), last from 0 dB (1.0)
        expect(peaks.first).to be < 0.05
        expect(peaks.last).to be_within(0.01).of(1.0)
      end
    end

    context 'when ffmpeg exits non-zero (corrupted audio)' do
      it 'returns []' do
        status = instance_double(Process::Status, success?: false)
        allow(Open3).to receive(:capture3).and_return(['', 'invalid data', status])
        allow(File).to receive(:exist?).and_return(true)

        expect(described_class.new(fixture_path).extract).to eq([])
      end
    end

    context 'when ffmpeg succeeds but emits no peaks' do
      it 'returns []' do
        status = instance_double(Process::Status, success?: true)
        allow(Open3).to receive(:capture3).and_return(['', 'no peaks here', status])
        allow(File).to receive(:exist?).and_return(true)

        expect(described_class.new(fixture_path).extract).to eq([])
      end
    end

    context 'when ffmpeg times out' do
      it 'logs a warning, kills the subprocess and returns []' do
        allow(File).to receive(:exist?).and_return(true)
        allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

        expect(Rails.logger).to receive(:warn).with(/timed out/)
        expect(described_class.new(fixture_path).extract).to eq([])
      end
    end

    context 'when ffmpeg reports -inf dB (digital silence)' do
      it 'treats it as 0.0 amplitude' do
        stderr = (1..64).map { '[astats] Peak level dB: -inf' }.join("\n")
        status = instance_double(Process::Status, success?: true)
        allow(Open3).to receive(:capture3).and_return(['', stderr, status])
        allow(File).to receive(:exist?).and_return(true)

        peaks = described_class.new(fixture_path).extract
        expect(peaks).to all(eq(0.0))
        expect(peaks.size).to eq(described_class::PEAK_COUNT)
      end
    end

    context 'when ffmpeg returns fewer peaks than PEAK_COUNT' do
      it 'pads with zeros at the tail' do
        stderr = (1..10).map { '[astats] Peak level dB: -6.020600' }.join("\n")
        status = instance_double(Process::Status, success?: true)
        allow(Open3).to receive(:capture3).and_return(['', stderr, status])
        allow(File).to receive(:exist?).and_return(true)

        peaks = described_class.new(fixture_path).extract
        expect(peaks.size).to eq(described_class::PEAK_COUNT)
        # First 10 are ~0.5 (linear of -6.02 dB), the rest zero
        expect(peaks.first(10)).to all(be_within(0.01).of(0.5))
        expect(peaks.last(described_class::PEAK_COUNT - 10)).to all(eq(0.0))
      end
    end
  end

  describe 'FFMPEG_PATH override' do
    it 'uses ENV[FFMPEG_PATH] when present' do
      allow(File).to receive(:exist?).and_return(true)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('FFMPEG_PATH', 'ffmpeg').and_return('/opt/ffmpeg/bin/ffmpeg')

      expect(Open3).to receive(:capture3).with(
        '/opt/ffmpeg/bin/ffmpeg', any_args
      ).and_return(['', '', instance_double(Process::Status, success?: false)])

      described_class.new('/tmp/audio.ogg').extract
    end
  end
end

# Minimal, dependency-free vCard parser.
#
# Handles vCard 2.1 / 3.0 / 4.0, CRLF or LF line endings, line folding,
# property groups (item1.TEL), parameters (TEL;TYPE=CELL) and QUOTED-PRINTABLE
# encoded values (common in 2.1 for accented names). A single file may contain
# several vCards (multiple BEGIN:VCARD blocks) — each becomes one entry.
#
# #parse returns an Array of Hashes (one per card):
#   { first_name:, last_name:, full_name:, phone:, phones:, organization:, email:, photo: }
# keys with blank values are omitted.
class Vcard::ParserService
  # Skip inline base64 photos larger than this (encoded length) so we don't
  # inflate the message JSON. URL-based photos are always kept.
  MAX_INLINE_PHOTO_BYTES = 24_000

  RECOGNISED_PROPERTIES = %w[BEGIN END VERSION FN N TEL ORG EMAIL PHOTO].freeze

  def initialize(raw)
    @raw = raw.to_s
  end

  def parse
    cards.filter_map { |card| parse_card(card) }
  end

  private

  # Split into individual vCards. A `.vcf` can legitimately hold several.
  def cards
    normalized = @raw.gsub("\r\n", "\n").tr("\r", "\n")
    normalized.scan(/BEGIN:VCARD.*?END:VCARD/mi)
  end

  def parse_card(card)
    props = unfold(card).filter_map { |line| parse_line(line) }
    return if props.empty?

    tels = props.select { |p| p[:name] == 'TEL' }.pluck(:value).reject(&:blank?)
    first_name, last_name = names(prop(props, 'N'), prop(props, 'FN'))
    full = full_name(prop(props, 'FN'), first_name, last_name)
    return if full.blank? && tels.empty?

    build_contact(props, tels, first_name, last_name, full)
  end

  def build_contact(props, tels, first_name, last_name, full)
    {
      first_name: first_name.presence,
      last_name: last_name.presence,
      full_name: full.presence,
      phone: tels.first,
      phones: tels,
      organization: organization(prop(props, 'ORG')),
      email: prop(props, 'EMAIL')&.dig(:value).presence,
      photo: photo_value(prop(props, 'PHOTO'))
    }.compact
  end

  def prop(props, name)
    props.find { |p| p[:name] == name }
  end

  # RFC line unfolding: a line starting with space/tab continues the previous one.
  def unfold(card)
    card.split("\n").each_with_object([]) do |line, acc|
      if acc.any? && line.start_with?(' ', "\t")
        acc[-1] += line.sub(/\A[ \t]/, '')
      else
        acc << line
      end
    end
  end

  def parse_line(line)
    return if line.blank?

    idx = line.index(':')
    return if idx.nil?

    prefix = line[0...idx]
    raw_value = line[(idx + 1)..]

    parts = prefix.split(';')
    name = parts.shift.to_s
    name = name.split('.').last.to_s if name.include?('.') # drop group prefix (item1.TEL)
    name = name.upcase
    return unless RECOGNISED_PROPERTIES.include?(name)

    params = parts.map(&:upcase)
    { name: name, params: params, value: decode_value(raw_value, params, name).to_s.strip }
  end

  def decode_value(value, params, name)
    # Never QP-decode a PHOTO payload (it may contain '=' as base64 padding).
    return value if name == 'PHOTO'
    return value unless params.any? { |p| p.include?('QUOTED-PRINTABLE') }

    decoded = value.unpack1('M*')
    decoded&.force_encoding('UTF-8')
  rescue StandardError
    value
  end

  def names(n_prop, fn_prop)
    if n_prop
      # N: Family;Given;Additional;Prefix;Suffix
      comps = n_prop[:value].split(';')
      family = comps[0].to_s.strip
      given = comps[1].to_s.strip
      return [given, family] if given.present? || family.present?
    end

    return ['', ''] if fn_prop.nil? || fn_prop[:value].blank?

    tokens = fn_prop[:value].strip.split(/\s+/)
    return [tokens.first, ''] if tokens.size == 1

    [tokens.first, tokens[1..].join(' ')]
  end

  def full_name(fn_prop, first, last)
    return fn_prop[:value].strip if fn_prop && fn_prop[:value].present?

    "#{first} #{last}".strip
  end

  def organization(org_prop)
    return if org_prop.nil?

    org_prop[:value].split(';').map(&:strip).reject(&:blank?).first
  end

  def photo_value(photo_prop)
    return if photo_prop.nil?

    value = photo_prop[:value]
    return if value.blank?
    return value if value.start_with?('http://', 'https://', 'data:')
    # vCard 4.0 URI photos.
    return value if photo_prop[:params].any? { |p| p.start_with?('VALUE=URI') }
    # Inline base64 (vCard 2.1/3.0) — keep only if small.
    return if value.length > MAX_INLINE_PHOTO_BYTES

    "data:#{photo_mime(photo_prop[:params])};base64,#{value}"
  end

  def photo_mime(params)
    type = params.find { |p| p.start_with?('TYPE=') || %w[JPEG PNG GIF].include?(p) }
    subtype = type.to_s.sub('TYPE=', '').downcase
    subtype = 'jpeg' if subtype.blank? || subtype == 'jpg'
    "image/#{subtype}"
  end
end

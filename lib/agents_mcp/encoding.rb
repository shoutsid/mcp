# frozen_string_literal: true

module AgentsMcp
  #
  # A report id or a symbol carrying either would reach a different path here than there,
  # which is the class of difference a port exists to remove.
  module Encoding
    UNRESERVED = ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a + %w[_ . - ~]

    def self.hex(byte)
      format("%%%02X", byte)
    end

    def self.quote(value, safe: "")
      allowed = UNRESERVED + safe.chars
      value.to_s.b.each_char.map { |char| allowed.include?(char) ? char : hex(char.ord) }.join
    end

    def self.quote_plus(value)
      value.to_s.b.each_char.map do |char|
        case char
        when " " then "+"
        else UNRESERVED.include?(char) ? char : hex(char.ord)
        end
      end.join
    end

    # A nil value is dropped, the way httpx drops it.
    def self.urlencode(pairs)
      pairs.filter_map do |key, value|
        next if value.nil?

        "#{quote_plus(key)}=#{quote_plus(value)}"
      end.join("&")
    end
  end
end

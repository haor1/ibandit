module Ibandit
  class SwedishDetailsConverter
    # Converts local Swedish details into SWIFT details.
    #
    # Local details can be provided as either:
    # - branch_code: clearing number, account_number: serial number
    # - banch_code: nil, account_number: #{clearing number}#{serial number}
    #
    # The reverse conversion (extracting local details from SWIFT details) is
    # not possible, since the clearing number cannot be derived. You should NOT
    # ever pass this class a SWIFT account number, as it will not convert
    # it to local details successfully.
    def initialize(branch_code: nil, account_number: nil)
      @branch_code = branch_code
      @account_number = account_number
    end

    def convert
      if bank_info.nil?
        return { swift_bank_code: nil,
                 swift_account_number: cleaned_account_number.rjust(17, '0') }
      end

      {
        account_number: serial_number,
        branch_code: clearing_code,
        swift_bank_code: bank_info.fetch(:bank_code).to_s,
        swift_account_number: swift_account_number
      }
    end

    private

    def cleaned_account_number
      # Don't trim leading zeroes if the account number we are given is a
      # serial number (i.e. if the clearing code is separate).
      @cleaned_account_number ||= remove_bad_chars(@account_number)
    end

    def cleaned_branch_code
      @cleaned_branch_code ||= remove_bad_chars(@branch_code)
    end

    def remove_bad_chars(number)
      return if number.nil?
      number.gsub(/[-.\s]/, '')
    end

    def bank_info
      @bank_info ||= self.class.bank_info_for(bank_info_key)
    end

    def bank_info_key
      (cleaned_branch_code || cleaned_account_number).slice(0, 4)
    end

    def clearing_code_length
      bank_info.fetch(:clearing_code_length)
    end

    def serial_number_length
      bank_info.fetch(:serial_number_length)
    end

    def clearing_code
      cleaned_branch_code ||
        cleaned_account_number.slice(0, clearing_code_length)
    end

    def serial_number
      serial_number = if @branch_code.nil?
                        cleaned_account_number[clearing_code_length..-1]
                      else
                        cleaned_account_number
                      end

      return serial_number unless bank_info.fetch(:zerofill_serial_number)

      serial_number.rjust(serial_number_length, '0')
    end

    def swift_account_number
      if bank_info.fetch(:include_clearing_code)
        (clearing_code + serial_number).rjust(17, '0')
      else
        serial_number.rjust(17, '0')
      end
    end

    def self.valid_bank_code?(bank_code: nil, account_number: nil)
      possible_bank_infos = possible_bank_info_for(
        bank_code: bank_code, account_number: account_number
      )

      possible_bank_infos.any?
    end

    def self.valid_length?(bank_code: nil, account_number: nil)
      return unless valid_bank_code?(
        bank_code: bank_code, account_number: account_number
      )

      cleaned_account_number = account_number.gsub(/\A0+/, '')

      possible_bank_infos = possible_bank_info_for(
        bank_code: bank_code, account_number: account_number
      )

      possible_bank_infos.any? do |bank|
        length = bank.fetch(:serial_number_length)
        length += bank[:clearing_code_length] if bank[:include_clearing_code]

        if bank[:zerofill_serial_number] && !bank[:include_clearing_code]
          serial_number_length = bank.fetch(:serial_number_length)
          cleaned_account_number =
            cleaned_account_number.rjust(serial_number_length, '0')
        end

        cleaned_account_number.length == length
      end
    end

    def self.bank_info_for(clearing_code)
      bank_info_table.find { |bank| bank[:range].include?(clearing_code.to_i) }
    end

    def self.possible_bank_info_for(bank_code: nil, account_number: nil)
      clearing_number = account_number.gsub(/\A0+/, '').slice(0, 4).to_i

      possible_bank_infos = bank_info_table.select do |bank|
        bank.fetch(:bank_code).to_s == bank_code
      end

      possible_bank_infos.select do |bank|
        !bank[:include_clearing_code] || bank[:range].include?(clearing_number)
      end
    end
    private_class_method :possible_bank_info_for

    def self.bank_info_table
      @swedish_bank_lookup ||=
        begin
          relative_path = '../../../data/raw/swedish_bank_lookup.yml'
          raw_info = YAML.load_file(File.expand_path(relative_path, __FILE__))

          raw_info.map { |bank| bank.merge(range: Range.new(*bank[:range])) }
        end
    end
    private_class_method :bank_info_table
  end
end

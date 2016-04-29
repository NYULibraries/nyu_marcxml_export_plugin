class NYUCustomTag
  attr_reader :tag_info, :subfield_info

  def initialize(tag_info,subfield_info)
    @tag_info = tag_info
    @subfield_info = subfield_info
    @error_messages = []
    # validates tag and subfield hashes
    check_class_arguments
    @tag= tag_info[:tag]
    @ind1 = tag_info[:ind1]
    @ind2 = tag_info[:ind2]
  end

  def add_tag
    set_datafield
  end

  private
    # sorts keys by order
    # creates a new subfield instance
    def set_subfields
      subfield = Struct.new(:code, :text)
      subfield_list = []
      @subfield_info.keys.sort.each { |k|
        code = @subfield_info[k][:code]
        value = @subfield_info[k][:value]
        subfield_list << subfield.new(code,value)
      }
      subfield_list
    end

    def set_datafield
      datafield = Struct.new(:tag, :ind1, :ind2, :subfields)
      subfields = set_subfields
      datafield.new(@tag,@ind1,@ind2,subfields)
    end

    def check_class_arguments
      check_tag_info
      check_subfield_info
      unless @error_messages.empty?
        get_err_messages
      end
    end

    def check_tag_info
      check_data_type(@tag_info)
      valid_values = [:tag,:ind1,:ind2]
      is_valid?(@tag_info.keys,valid_values)
    end

    def check_subfield_info
      check_data_type(@subfield_info)
      valid_values = [:code,:value]
      @subfield_info.each_pair { |k,hsh|
        unless k.is_a?(Integer)
          err = "ERROR: subfield hash needs integers for keys: #{k}"
          send_err_messages(err)
        end
        is_valid?(hsh.keys,valid_values)
      }

    end

    def check_data_type(data)
      unless data.is_a?(Hash)
        err = "ERROR: #{data} needs to be a Hash"
        send_err_messages(err)
      end
      true
    end

    def is_valid?(test_values,valid_values)
      check = test_values - valid_values
      unless check.empty?
        err = "ERROR: #{test_values} needs to have the following values: #{valid_values}"
        send_err_messages(err)
      end
      true
    end

    def send_err_messages(msg)
      @error_messages << msg
    end

    def get_err_messages
      err = "Errors found in class #{self.class.name}: "
      err += @error_messages.join(", ")
      raise err
    end

end

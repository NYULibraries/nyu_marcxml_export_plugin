class NYUCustomTag
  attr_reader :tag_info, :subfield_info

  def initialize(tag_info, *args)
    @tag_info = tag_info
    @subfield_info = args.shift
    @error_messages = []
    check_class_arguments
  end

  def add_datafield_tag
    set_datafield
  end

  def add_controlfield_tag
    set_controlfield
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
    tag = @tag_info[:tag]
    ind1 = @tag_info[:ind1]
    ind2 = @tag_info[:ind2]
    datafield.new(tag,ind1,ind2,subfields)
  end

  def set_controlfield
    controlfield = Struct.new(:tag, :text)
    controlfield.new(@tag_info[:tag],@tag_info[:text])
  end

  def check_class_arguments
    check_tag_info
    check_subfield_info if @subfield_info
    unless @error_messages.empty?
      get_err_messages
    end
  end

  def check_tag_info
    check_data_type(@tag_info)
    if @tag_info.keys.size == 2
      check_controlfield_hash
    else
      check_datafield_hash
    end
  end

  def check_controlfield_hash
    valid_values = valid_controlfield_values
    is_valid?(@tag_info.keys,valid_values)
  end

  def check_datafield_hash
    valid_values = valid_datafield_values
    is_valid?(@tag_info.keys,valid_values)
  end

  def valid_controlfield_values
    [:tag, :text]
  end

  def valid_datafield_values
    [:tag, :ind1, :ind2]
  end

  def valid_subfield_values
    [:code, :value]
  end

  def check_subfield_info
    check_data_type(@subfield_info)
    valid_values = valid_subfield_values
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

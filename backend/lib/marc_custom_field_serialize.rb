class MARCCustomFieldSerialize
  ControlField = Struct.new(:tag, :text)
  DataField = Struct.new(:tag, :ind1, :ind2, :subfields)
  SubField = Struct.new(:code, :text)

  def initialize(record)
    @record = record

  end

  def leader_string
    result = @record.leader_string
  end

  def controlfield_string
    result = @record.controlfield_string
  end

  def datafields
    extra_fields = []
    extra_fields << add_853_tag
    if @record.aspace_record['top_containers']
      top_containers = @record.aspace_record['top_containers']
      top_containers.each_key{ |id|
        info = top_containers[id]
        extra_fields << add_863_tag(info)
        extra_fields << add_949_tag(info)
      }
    end
    (@record.datafields + extra_fields).sort_by(&:tag)
  end

  def get_datafield_hash(tag,ind1,ind2)
    {tag: tag, ind1: ind1, ind2: ind2}
  end

  def get_subfield_hash(code,value)
    {code:code, value:value}
  end

  def add_853_tag
    subfields_hsh = {}
    datafields_hsh = {}
    datafield_hsh = get_datafield_hash('853','0','0')
    # have to have a hash by position as the key
    # since the subfield positions matter
    subfields_hsh[1] = get_subfield_hash('8','1')
    subfields_hsh[2] = get_subfield_hash('a','Box')
    datafield = NYUCustomTag.new(datafield_hsh,subfields_hsh)
    datafield.add_tag
  end

  def add_863_tag(info)
    subfields_hsh = {}
    datafield_hsh = get_datafield_hash('863','','')
    # have to have a hash by position as the key
    # since the subfield positions matter
    subfields_hsh[1] = get_subfield_hash('8',"1.#{info[:indicator]}")
    subfields_hsh[2] = get_subfield_hash('a',info[:indicator])
    subfields_hsh[3] = get_subfield_hash('p',info[:barcode]) if info[:barcode]
    datafield = NYUCustomTag.new(datafield_hsh,subfields_hsh)
    datafield.add_tag
  end

  def add_949_tag(info)
    subfields_hsh = {}
    datafield_hsh = get_datafield_hash('949','0','')
    # have to have a hash by position as the key
    # since the subfield positions matter
    subfields_hsh[1] = get_subfield_hash('a','NNU')
    subfields_hsh[4] = get_subfield_hash('t','4')
    subfields_hsh[5] = check_multiple_ids
    subfields_hsh[6] = get_subfield_hash('m','MIXED')
    subfields_hsh[7] = get_subfield_hash('i','04')
    subfields_hsh[8] = get_location(info[:location])
    subfields_hsh[9] = get_subfield_hash('p',info[:barcode]) if info[:barcode]
    subfields_hsh[10] = get_subfield_hash('w',"Box #{info[:indicator]}")
    subfields_hsh[11] = get_subfield_hash('e',info[:indicator])
    # merge repo code hash with existing subfield code hash
    subfields_hsh.merge!(process_repo_code)
    datafield = NYUCustomTag.new(datafield_hsh,subfields_hsh)
    datafield.add_tag
  end

  def get_record_repo_value
    # returning the repo value from the record
    # in a consistent case
    code = @record.aspace_record['repository']['_resolved']['repo_code']
    value = code == code.downcase ? code : code.downcase
    value
  end

  def get_allowed_values
    allowed_values = {}
    allowed_values['tamwag'] = { b: 'BTAM', c: 'TAM' }
    allowed_values['fales'] = { b: 'BFALE', c: 'FALES'}
    allowed_values['archives'] = { b: 'BOBST', c: 'ARCH' }
    allowed_values
  end

  def get_repo_code_values
    repo_code = nil
    record_repo_value = get_record_repo_value
    # get valid values
    allowed_values = get_allowed_values
    # get subfield values for repo codes
    allowed_values.each_key { |code|
      case record_repo_value
      when code
        repo_code = allowed_values[code]
      end
    }
    unless repo_code
      raise "ERROR: Repo code must be one of these: #{allowed_values.keys}
      and not this value: #{record_repo_value}"
    end
    repo_code
  end

  def process_repo_code
    subfields = {}
    # get subfield values for repo code
    repo_code = get_repo_code_values
    # creating a subfield hash
    repo_code.each_key{ |code|
      position = code.to_s == 'b' ? 2 : 3
      subfields[position] = get_subfield_hash(code,repo_code[code])
    }
    subfields
  end

  def check_multiple_ids
    j_id = @record.aspace_record['id_0']
    j_other_ids = []
    if @record.aspace_record['id_1'] or @record.aspace_record['id_2'] or
      @record.aspace_record['id_3']
      j_other_ids << @record.aspace_record['id_1']
      j_other_ids << @record.aspace_record['id_2']
      j_other_ids << @record.aspace_record['id_3']
      # adding the first id as the first element of the array
      j_other_ids.unshift(j_id)
      j_other_ids.compact!
      j_other_ids = j_other_ids.join(".")
    end
    # if no other ids, assign id_0 else assign the whole array of ids
    j_id = j_other_ids.size == 0 ? j_id : j_other_ids
    # creating a subfield hash
    get_subfield_hash('j',j_id)

  end

  def get_location(location_info)
    # if location is Clancy Cullen,
    # output VH
    # else a blank subfield
    location = location_info == 'Clancy Cullen' ? 'VH' : ''
    # creating a subfield hash
    get_subfield_hash('s',location)
  end

end

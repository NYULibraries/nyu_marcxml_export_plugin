class MARCModel < ASpaceExport::ExportModel
  model_for :marc21

  include JSONModel

  def self.df_handler(name, tag, ind1, ind2, code)
    define_method(name) do |val|
      df(tag, ind1, ind2).with_sfs([code, val])
    end
    name.to_sym
  end

  @archival_object_map = {
      [:repository, :finding_aid_language] => :handle_repo_code,
      [:title, :linked_agents, :dates] => :handle_title,
      :linked_agents => :handle_agents,
      :subjects => :handle_subjects,
      :extents => :handle_extents,
      :lang_materials => :handle_languages
  }

  @resource_map = {
      [:id_0, :id_1, :id_2, :id_3] => :handle_id,
      [:ead_location] => :handle_ead_loc,
      [:id, :jsonmodel_type] => :handle_ark,
      :notes => :handle_notes,
      :finding_aid_description_rules => df_handler('fadr', '040', ' ', ' ', 'e')
  }

  attr_accessor :leader_string
  attr_accessor :controlfield_string

  @@datafield = Class.new do

    attr_accessor :tag
    attr_accessor :ind1
    attr_accessor :ind2
    attr_accessor :subfields


    def initialize(*args)
      @tag, @ind1, @ind2 = *args
      @subfields = []
    end

    def with_sfs(*sfs)
      sfs.each do |sf|
        subfield = @@subfield.new(*sf)
        @subfields << subfield unless subfield.empty?
      end

      return self
    end

  end

  @@subfield = Class.new do

    attr_accessor :code
    attr_accessor :text

    def initialize(*args)
      @code, @text = *args
    end

    def empty?
      if @text && !@text.empty?
        false
      else
        true
      end
    end
  end

  def initialize(include_unpublished = false)
    @datafields = {}
    @include_unpublished = include_unpublished
  end

  def datafields
    @datafields.map {|k,v| v}
  end

  def include_unpublished?
    @include_unpublished
  end


  def self.from_aspace_object(obj, opts = {})
    self.new(opts[:include_unpublished])
  end

  # 'archival object's in the abstract
  def self.from_archival_object(obj, opts = {})

    marc = self.from_aspace_object(obj, opts)
    marc.apply_map(obj, @archival_object_map)

    marc
  end

  # subtypes of 'archival object':

  def self.from_resource(obj, opts = {})
    marc = self.from_archival_object(obj, opts)
    marc.apply_map(obj, @resource_map)
    marc.leader_string = "00000np$aa2200000 u 4500"
    marc.leader_string[7] = obj.level == 'item' ? 'm' : 'c'

    marc.controlfield_string = assemble_controlfield_string(obj)

    marc
  end

  def self.assemble_controlfield_string(obj)

    date = obj.dates[0] || {}
    string = obj['system_mtime'].scan(/\d{2}/)[1..3].join('')
    string += obj.level == 'item' && date['date_type'] == 'single' ? 's' : 'i'
    string += date['begin'] ? date['begin'][0..3] : "    "
    string += date['end'] ? date['end'][0..3] : "    "

    repo = obj['repository']['_resolved']

    if repo.has_key?('country') && !repo['country'].empty?
      # US is a special case, because ASpace has no knowledge of states, the
      # correct value is 'xxu'
      if repo['country'] == "US"
        string += "xxu"
      else
        string += repo['country'].downcase
      end
    else
      string += "xx"
    end

    # If only one Language and Script subrecord its code value should be exported in the MARC 008 field position 35-37; If more than one Language and Script subrecord is recorded, a value of "mul" should be exported in the MARC 008 field position 35-37.
    lang_materials = obj.lang_materials
    languages = lang_materials.map{|l| l['language_and_script']}.compact
    langcode = languages.count == 1 ? languages[0]['language'] : 'mul'

    # variable number of spaces needed since country code could have 2 or 3 chars
    (35-(string.length)).times { string += ' ' }
    string += (langcode || '|||')
    string += ' d'

    string

  end

  def df!(*args)
    @sequence ||= 0
    @sequence += 1
    @datafields[@sequence] = @@datafield.new(*args)
    @datafields[@sequence]
  end


  def df(*args)
    if @datafields.has_key?(args.to_s)
      @datafields[args.to_s]
    else
      @datafields[args.to_s] = @@datafield.new(*args)
      @datafields[args.to_s]
    end
  end

  def handle_id(*ids)
    ids.reject!{|i| i.nil? || i.empty?}
    df('099', ' ', ' ').with_sfs(['a', ids.join('.')])
  end

  def handle_title(title, linked_agents, dates)
    creator = linked_agents.find{|a| a['role'] == 'creator'}
    date_codes = []

    # process dates first, if defined.
    unless dates.empty?
      dates = [["single", "inclusive", "range"], ["bulk"]].map {|types|
        dates.find {|date| types.include? date['date_type'] }
      }.compact

      dates.each do |date|
        code, val = nil
        code = date['date_type'] == 'bulk' ? 'g' : 'f'
        if date['expression']
          val = date['expression']
        elsif date['end']
          val = "#{date['begin']} - #{date['end']}"
        else
          val = "#{date['begin']}"
        end
        date_codes.push([code, val])
      end
    end

    ind1 = creator.nil? ? "0" : "1"
    if date_codes.length > 0
      # we want to pass in all our date codes as separate subfield tags
      # e.g., with_sfs(['a', title], [code1, val1], [code2, val2]... [coden, valn])
      df('245', ind1, '0').with_sfs(['a', title + ","], *date_codes)
    else
      df('245', ind1, '0').with_sfs(['a', title])
    end
  end

  def handle_languages(lang_materials)

    # ANW-697: The Language subrecord code values should be exported in repeating subfield $a entries in the MARC 041 field.

    languages = lang_materials.map{|l| l['language_and_script']}.compact

    languages.each do |language|

      df('041', ' ', ' ').with_sfs(['a', language['language']])

    end

    # ANW-697: Language Text subrecords should be exported in the MARC 546 subfield $a

    language_notes = lang_materials.map {|l| l['notes']}.compact.reject {|e|  e == [] }

    if language_notes
      language_notes.each do |note|
        handle_notes(note)
      end
    end

  end

  def handle_dates(dates)
    return false if dates.empty?

    dates = [["single", "inclusive", "range"], ["bulk"]].map {|types|
      dates.find {|date| types.include? date['date_type'] }
    }.compact
    chk_array = []
    dates.each { |d|
      d.keys.each { |k|
        chk_array << [k,d[k]]  if (k =~ /date/ && d[k] == 'bulk')
      }
    }
    chk_array.flatten!
    dates.each do |date|
      code = date['date_type'] == 'bulk' ? 'g' : 'f'
      val = nil
      if date['expression'] && date['date_type'] != 'bulk'
        val = date['expression']
      elsif date['date_type'] == 'single'
        val = date['begin']
      elsif date['begin'] == date['end']
        val = "(bulk #{date['begin']})."
      else
        if code == 'f'
          val = "#{date['begin']}-#{date['end']}"
        elsif code == 'g'
          val = "(bulk #{date['begin']}-#{date['end']})."
        end
      end
      val += "." if code == 'f' && not(chk_array.include?("bulk"))
      df('245', '1', '0').with_sfs([code, val])
    end
  end

  def handle_repo_code(repository, *finding_aid_language)
    repo = repository['_resolved']
    return false unless repo

    sfa = repo['org_code'] ? repo['org_code'] : "Repository: #{repo['repo_code']}"

    # ANW-529: options for 852 datafield:
    # 1.) $a => org_code || repo_name
    # 2.) $a => $parent_institution_name && $b => repo_name

    if repo['parent_institution_name']
      subfields_852 = [
          ['a', repo['parent_institution_name']],
          ['b', repo['name']]
      ]
    elsif repo['org_code']
      subfields_852 = [
          ['a', repo['org_code']],
      ]
    else
      subfields_852 = [
          ['a', repo['name']]
      ]
    end

    df('852', ' ', ' ').with_sfs(*subfields_852)
    df('040', ' ', ' ').with_sfs(['a', repo['org_code']], ['b', finding_aid_language[0]],['c', repo['org_code']])
    df('049', ' ', ' ').with_sfs(['a', repo['org_code']])

    if repo.has_key?('country') && !repo['country'].empty?

      # US is a special case, because ASpace has no knowledge of states, the
      # correct value is 'xxu'
      if repo['country'] == "US"
        df('044', ' ', ' ').with_sfs(['a', "xxu"])
      else
        df('044', ' ', ' ').with_sfs(['a', repo['country'].downcase])
      end
    end
  end

  def source_to_code(source)
    ASpaceMappings::MARC21.get_marc_source_code(source)
  end

  def handle_subjects(subjects)
    subjects.each do |link|
      subject = link['_resolved']
      term, *terms = subject['terms']
      ind1 = ' '
      code, *ind2 =  case term['term_type']
                     when 'uniform_title'
                       value = term['term'].split(" ")[0]
                       first_indicator = '0'
                       if value
                         hsh = {}
                         hsh['A'] = '2'
                         hsh['An'] = '3'
                         hsh['The'] = '4'
                         articles = []
                         articles = hsh.keys
                         first_indicator = hsh[value] if articles.include?(value)
                       end
                       ['630', first_indicator, source_to_code(subject['source'])]
                     when 'temporal'
                       ['648', source_to_code(subject['source'])]
                     when 'topical'
                       ['650', source_to_code(subject['source'])]
                     when 'geographic', 'cultural_context'
                       ['651', source_to_code(subject['source'])]
                     when 'genre_form', 'style_period'
                       ['655', source_to_code(subject['source'])]
                     when 'occupation'
                       ['656', '7']
                     when 'function'
                       ['656', '7']
                     else
                       ['650', source_to_code(subject['source'])]
                     end

      sfs = [['a', term['term']]]

      terms.each do |t|
        tag = case t['term_type']
              when 'uniform_title'; 't'
              when 'genre_form', 'style_period'; 'v'
              when 'topical', 'cultural_context'; 'x'
              when 'temporal'; 'y'
              when 'geographic'; 'z'
              end
        sfs << [tag, t['term']]
      end

      # N.B. ind2 is an array at this point.
      if ind2[0] == '7'
        sfs << ['2', subject['source']]
      end

      # adding this code snippet because I'm making ind2 an array
      # for code 630 if the title begins with an article
      if (ind2.is_a?(Array) && code == '630')
        ind1, ind2 = ind2
      else
        ind2 = ind2[0]
      end

      df!(code, ind1, ind2).with_sfs(*sfs)
    end
  end

  def handle_primary_creator(linked_agents)
    link = linked_agents.find{|a| a['role'] == 'creator'}
    return nil unless link
    return nil unless link["_resolved"]["publish"] || @include_unpublished

    creator = link['_resolved']
    name = creator['display_name']

    ind2 = ' '

    if link['relator']
      relator = I18n.t("enumerations.linked_agent_archival_record_relators.#{link['relator']}")
      role_info = ['4', relator]
    else
      role_info = ['e', 'creator']
    end

    case creator['agent_type']

    when 'agent_corporate_entity'
      code = '110'
      ind1 = '2'
      sfs = gather_agent_corporate_subfield_mappings(name, role_info, creator)

    when 'agent_person'
      ind1  = name['name_order'] == 'direct' ? '0' : '1'
      code = '100'
      sfs = gather_agent_person_subfield_mappings(name, role_info, creator)

    when 'agent_family'
      code = '100'
      ind1 = '3'
      sfs = gather_agent_family_subfield_mappings(name, role_info, creator)

    end

    df(code, ind1, ind2).with_sfs(*sfs)
  end

  # TODO: DRY this up
  # this method is very similair to handle_primary_creator and handle_agents

  def handle_other_creators(linked_agents)
    creators = linked_agents.select{|a| a['role'] == 'creator'}[1..-1] || []
    creators = creators + linked_agents.select{|a| a['role'] == 'source'}

    creators.each_with_index do |link, i|
      next unless link["_resolved"]["publish"] || @include_unpublished

      creator = link['_resolved']
      name = creator['display_name']
      terms = link['terms']
      role = link['role']

      if link['relator']
        relator_sf = ['4', link['relator']]
      elsif role == 'source'
        relator_sf =  ['e', 'former owner']
      else
        relator_sf = ['e', 'creator']
      end

      ind2 = ' '

      case creator['agent_type']

      when 'agent_corporate_entity'
        code = '710'
        ind1 = '2'
        sfs = gather_agent_corporate_subfield_mappings(name, relator_sf, creator)

      when 'agent_person'
        ind1  = name['name_order'] == 'direct' ? '0' : '1'
        code = '700'
        sfs = gather_agent_person_subfield_mappings(name, relator_sf, creator)

      when 'agent_family'
        ind1 = '3'
        code = '700'
        sfs = gather_agent_family_subfield_mappings(name, relator_sf, creator)

      end

      df(code, ind1, ind2, i).with_sfs(*sfs)
    end
  end

  def handle_agents(linked_agents)

    handle_primary_creator(linked_agents)
    handle_other_creators(linked_agents)

    subjects = linked_agents.select{|a| a['role'] == 'subject'}

    subjects.each_with_index do |link, i|
      subject = link['_resolved']
      name = subject['display_name']

      if link['relator']
        relator = I18n.t("enumerations.linked_agent_archival_record_relators.#{link['relator']}")
        relator_sf = ['4', relator]
      end

      terms = link['terms']

      def handle_repo_code(repository, *finding_aid_language)
        repo = repository['_resolved']
        return false unless repo

        sfa = repo['org_code'] ? repo['org_code'] : "Repository: #{repo['repo_code']}"

        # ANW-529: options for 852 datafield:
        # 1.) $a => org_code || repo_name
        # 2.) $a => $parent_institution_name && $b => repo_name

        if repo['parent_institution_name']
          subfields_852 = [
              ['a', repo['parent_institution_name']],
              ['b', repo['name']]
          ]
        elsif repo['org_code']
          subfields_852 = [
              ['a', repo['org_code']],
          ]
          elsea
          subfields_852 = [
              ['a', repo['name']]
          ]
        end

        df('852', ' ', ' ').with_sfs(*subfields_852)
        df('040', ' ', ' ').with_sfs(['a', repo['org_code']], ['b', finding_aid_language[0]],['c', repo['org_code']])
        df('049', ' ', ' ').with_sfs(['a', repo['org_code']])

        if repo.has_key?('country') && !repo['country'].empty?

          # US is a special case, because ASpace has no knowledge of states, the
          # correct value is 'xxu'
          if repo['country'] == "US"
            df('044', ' ', ' ').with_sfs(['a', "xxu"])
          else
            df('044', ' ', ' ').with_sfs(['a', repo['country'].downcase])
          end
        end
      end
      ind2 = source_to_code(name['source'])

      case subject['agent_type']

      when 'agent_corporate_entity'
        code = '610'
        ind1 = '2'
        sfs = [
            ['a', name['primary_name']],
            ['b', name['subordinate_name_1']],
            ['b', name['subordinate_name_2']],
            ['n', name['number']],
            ['g', name['qualifier']],
        ]

      when 'agent_person'
        joint, ind1 = name['name_order'] == 'direct' ? [' ', '0'] : [', ', '1']
        name_parts = [name['primary_name'], name['rest_of_name']].reject{|i| i.nil? || i.empty?}.join(joint)
        ind1 = name['name_order'] == 'direct' ? '0' : '1'
        code = '600'
        sfs = [
            ['a', name_parts],
            ['b', name['number']],
            ['c', %w(prefix title suffix).map {|prt| name[prt]}.compact.join(', ')],
            ['q', name['fuller_form']],
            ['d', name['dates']],
            ['g', name['qualifier']],
        ]

      when 'agent_family'
        code = '600'
        ind1 = '3'
        sfs = [
            ['a', name['family_name']],
            ['c', name['prefix']],
            ['d', name['dates']],
            ['g', name['qualifier']],
        ]

      end

      terms.each do |t|
        tag = case t['term_type']
              when 'uniform_title'; 't'
              when 'genre_form', 'style_period'; 'v'
              when 'topical', 'cultural_context'; 'x'
              when 'temporal'; 'y'
              when 'geographic'; 'z'
              end
        sfs << [(tag), t['term']]
      end

      if ind2 == '7'
        create_sfs2 = %w(local ingest)
        sfs << ['2', 'local'] if create_sfs2.include?(subject['display_name']['source'])
      end

      df(code, ind1, ind2, i).with_sfs(*sfs)
    end
  end


  def handle_notes(notes)

    notes.each do |note|

      prefix =  case note['type']
                when 'dimensions'; "Dimensions"
                when 'physdesc'; "Physical Description note"
                when 'materialspec'; "Material Specific Details"
                when 'physloc'; "Location of resource"
                when 'phystech'; "Physical Characteristics / Technical Requirements"
                when 'physfacet'; "Physical Facet"
                when 'processinfo'; "Processing Information"
                else; nil
                end

      marc_args = case note['type']

                  when 'arrangement', 'fileplan'
                    ['351','b']
                  when 'odd', 'dimensions', 'physdesc', 'materialspec', 'physloc', 'phystech', 'physfacet', 'processinfo'
                    ['500','a']
                  when 'accessrestrict'
                    ['506','a']
                  when 'abstract'
                    ['520', '3', ' ', 'a']
                  when 'prefercite'
                    ['524', '8', ' ', 'a']
                  when 'acqinfo'
                    ind1 = note['publish'] ? '1' : '0'
                    ['541', ind1, ' ', 'a']
                  when 'separatedmaterial'
                    ['544', '0', ' ', 'n']
                  when 'relatedmaterial'
                    ['544', '1', ' ', 'n']
                  when 'custodhist'
                    ind1 = note['publish'] ? '1' : '0'
                    ['561', ind1, ' ', 'a']
                  when 'appraisal'
                    ind1 = note['publish'] ? '1' : '0'
                    ['583', ind1, ' ', 'a']
                  when 'accruals'
                    ['584', 'a']
                  when 'altformavail'
                    ['535', '2', ' ', 'a']
                  when 'originalsloc'
                    ['535', '1', ' ', 'a']
                  when 'userestrict', 'legalstatus'
                    ['540', 'a']
                  when 'langmaterial'
                    ['546', 'a']
                  else
                    nil
                  end

      unless marc_args.nil?
        text = prefix ? "#{prefix}: " : ""
        text += ASpaceExport::Utils.extract_note_text(note, @include_unpublished, true)

        # only create a tag if there is text to show (e.g., marked published or exporting unpublished)
        if text.length > 0
          df!(*marc_args[0...-1]).with_sfs([marc_args.last, *Array(text)])
        end
      end

    end
  end

  def handle_ead_loc(ead_loc)
    df('555', ' ', ' ').with_sfs(
        ['a', "Finding aid online:"],
        ['u', ead_loc]
    )
    df('856', '4', '2').with_sfs(
        ['y', "Finding aid online"],
        ['u', ead_loc]
    )
  end


end

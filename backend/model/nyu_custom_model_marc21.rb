class MARCModel < ASpaceExport::ExportModel
  model_for :marc21

  include JSONModel

  @archival_object_map = {
    [:repository,:language] => :handle_repo_code,
    :title => :handle_title,
    :linked_agents => :handle_agents,
    :subjects => :handle_subjects,
    :extents => :handle_extents,
    :language => :handle_language,
    :dates => :handle_dates,
  }


  def self.assemble_controlfield_string(obj)
    date = obj.dates[0] || {}
    string = obj['system_mtime'].scan(/\d{2}/)[1..3].join('')
    string += date['date_type'] == 'single' ? 's' : 'i'
    string += date['begin'] ? date['begin'][0..3] : "    "
    string += date['end'] ? date['end'][0..3] : "    "
    string += "xx"
    18.times { string += ' ' }
    string += (obj.language || '|||')
    string += ' d'
    string
  end

  def handle_id(*ids)
    ids.reject!{|i| i.nil? || i.empty?}
    df('099', ' ', ' ').with_sfs(['a', ids.join('.')])
  end

  def handle_language(langcode)
    df('041', '0', ' ').with_sfs(['a', langcode])
  end

  def handle_repo_code(repository,langcode)
    repo = repository['_resolved']
    return false unless repo

    sfa = repo['org_code'] ? repo['org_code'] : "Repository: #{repo['repo_code']}"

    df('040', ' ', ' ').with_sfs(['a', repo['org_code']], ['b', langcode],['c', repo['org_code']])
  end

  def handle_agents(linked_agents)

    handle_primary_creator(linked_agents)

    subjects = linked_agents.select{|a| a['role'] == 'subject'}

    subjects.each_with_index do |link, i|
      subject = link['_resolved']
      name = subject['display_name']
      relator = link['relator']
      terms = link['terms']
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


    creators = linked_agents.select{|a| a['role'] == 'creator'}[1..-1] || []
    creators = creators + linked_agents.select{|a| a['role'] == 'source'}

    creators.each do |link|
      creator = link['_resolved']
      name = creator['display_name']
      relator = link['relator']
      terms = link['terms']
      role = link['role']

      if relator
        relator_sf = ['4', relator]
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
        code = '700'
        sfs = [
          ['a', name_parts],
          ['b', name['number']],
          ['c', %w(prefix title suffix).map {|prt| name[prt]}.compact.join(', ')],
          ['q', name['fuller_form']],
          ['d', name['dates']],
          ['g', name['qualifier']],
        ]

      when 'agent_family'
        ind1 = '3'
        code = '700'
        sfs = [
          ['a', name['family_name']],
          ['c', name['prefix']],
          ['d', name['dates']],
          ['g', name['qualifier']],
        ]
      end

      sfs << relator_sf
      df(code, ind1, ind2).with_sfs(*sfs)
    end

  end

  def handle_title(title)
    title += ","
    df('245', '1', '0').with_sfs(['a', title])
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

      if ind2 == '7'
        sfs << ['2', subject['source']]
      end
      # adding this code snippet because I'm making ind2 an array
      # for code 630 if the title begins with an article
      if (ind2.is_a?(Array) && code == '630')
        ind1,ind2 = ind2
      else
        ind2 = ind2[0]
      end
      df!(code, ind1, ind2).with_sfs(*sfs)
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
        text += ASpaceExport::Utils.extract_note_text(note)
        df!(*marc_args[0...-1]).with_sfs([marc_args.last, *Array(text)])
      end

    end
  end

end

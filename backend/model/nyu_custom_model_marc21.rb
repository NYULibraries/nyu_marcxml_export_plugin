class MARCModel < ASpaceExport::ExportModel
  model_for :marc21

  include JSONModel


  def handle_dates(dates)
    return false if dates.empty?

    dates = [["single", "inclusive", "range"], ["bulk"]].map {|types|
      dates.find {|date| types.include? date['date_type'] }
    }.compact

    dates.each do |date|
      code = date['date_type'] == 'bulk' ? 'g' : 'f'
      val = nil
      if date['expression'] && date['date_type'] != 'bulk'
        val = date['expression']
      elsif date['date_type'] == 'single'
        val = date['begin']
      else
        val = "#{date['begin']}-#{date['end']}"
      end

      df('245', '1', '0').with_sfs([code, val])
    end
  end

end

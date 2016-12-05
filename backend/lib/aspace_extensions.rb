require 'net/http/persistent'
module ExportHelpers

  ASpaceExport::init

  def generate_marc(id)
    @obj = resolve_references(Resource.to_jsonmodel(id),
    ['repository', 'linked_agents', 'subjects', 'instances',
      'tree'])
      tc_hash = process_top_containers
      @obj['top_containers'] = tc_hash unless tc_hash.nil?
      marc = ASpaceExport.model(:marc21).from_resource(JSONModel(:resource).new(@obj))
      ASpaceExport::serialize(marc)
  end

  def find_top_containers
    repo_id = @obj['repository']['_resolved']['uri'].split("/")[2]
    resource_id = @obj['uri']
    search_params = {}
    search_params['page'] = 1
    search_params[:type] = ['top_container']
    search_params[:filter_term] = [{"collection_uri_u_sstr" => resource_id}.to_json]
    top_container_results = nil
    TopContainer.search_stream(search_params,repo_id) do |response|
      top_container_results = JSON.parse(response.body)
    end
    top_container_results
  end

  def process_top_containers
    top_container_results = find_top_containers
    tc_info = {}
    top_containers = top_container_results['response']['docs']
    top_containers.each { |tc|
      data = JSON.parse(tc['json'])
      id = data['uri'] # top container uri
      indicator = data['indicator']
      hash = { indicator: data['indicator'] }
      if data['barcode']
        barcode = { barcode: data['barcode'] }
        hash = hash.merge(barcode)
      end
      tc_info[id] = hash
      location = data['container_locations'][0]
      tc_info[id].merge!({location: location['_resolved']['building']}) if location
    }
    tc_info
  end

end

class MARCModel < ASpaceExport::ExportModel
  attr_reader :aspace_record, :top_containers
  attr_accessor :controlfields
  def initialize(obj)
    @datafields = {}
    @controlfields = {}
    @aspace_record = obj
  end

  def self.from_aspace_object(obj)
    self.new(obj)
  end
end

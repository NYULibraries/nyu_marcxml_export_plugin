module ExportHelpers

  ASpaceExport::init

  def generate_marc(id)
    obj = resolve_references(Resource.to_jsonmodel(id),
    ['repository', 'linked_agents', 'subjects',
      'tree'])
      related_objects = get_related_objects(obj)
      containers = get_related_containers(related_objects) if related_objects
      if containers
        top_containers = get_top_containers(containers)
        obj[:top_containers]= get_locations(top_containers)
      end
      marc = ASpaceExport.model(:marc21).from_resource(JSONModel(:resource).new(obj))
      ASpaceExport::serialize(marc)
    end

    def get_related_objects(obj)
      obj['tree']['_resolved']['children']
    end

    def get_related_containers(related_objects)
      related_containers = []
      related_objects.each { |r|
        obj = resolve_references(ArchivalObject.to_jsonmodel(r['id']),
        ['top_container'])
        related_containers << obj['instances']
      }
      related_containers
    end

    def get_top_container_id(url)
      info = url.split('/')[4]
      info.to_i
    end

    def get_top_containers(related_containers)
      top_containers = {}
      related_containers.each{ |containers|
        containers.each{ |t|
          ref = t['sub_container']['top_container']['ref']
          tc_id = get_top_container_id(ref)
          barcode =  t['sub_container']['top_container']['_resolved']['barcode']
          indicator = t['sub_container']['top_container']['_resolved']['indicator']
          bc = {barcode: barcode} if barcode
          ind = {indicator: indicator}
          # if no barcode, just get indicator,
          # else, merge barcode with indicator in one hash
          tc_info = barcode.nil? ? ind : ind.merge(bc)
          top_containers[tc_id] = tc_info
        }
      }
      top_containers
    end

    def get_locations(top_containers)
      location = {}
      tc = top_containers.dup
      top_containers.each_key { |t|
        obj = resolve_references(TopContainer.to_jsonmodel(t),
        ['container_locations'])
        # if there's location information
        # continue processing
        if  obj['container_locations'][0]
          building = obj['container_locations'][0]['_resolved']['building']
          location = {location: building}
          tc[t] = top_containers[t].merge(location)
        end

      }
      tc
    end

  end

  class MARCModel < ASpaceExport::ExportModel
    attr_reader :aspace_record

    def initialize(obj)
      @datafields = {}
      @aspace_record = obj
    end


    def self.from_aspace_object(obj)
      self.new(obj)
    end

  end

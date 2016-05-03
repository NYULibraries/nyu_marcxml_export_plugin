module ExportHelpers

  ASpaceExport::init

  def generate_marc(id)
    obj = resolve_references(Resource.to_jsonmodel(id),
    ['repository', 'linked_agents', 'subjects',
      'tree'])
      # getting all ids for archival objects
      # at the lowest level, i.e. if there
      # is an array of hashes and the hashes
      # are nested, grabbing the ids from the
      # lowest level
      related_objects_ids = get_related_object_ids(obj)

      # grabbing containers for those ids
      containers = get_related_containers(related_objects_ids) if related_objects_ids

      # get top containers
      if containers
        top_containers = get_top_containers(containers)
        obj[:top_containers]= get_locations(top_containers)
      end
      marc = ASpaceExport.model(:marc21).from_resource(JSONModel(:resource).new(obj))
      ASpaceExport::serialize(marc)
    end

    # getting ids of all archival objects
    # that might contain top container references
    def get_related_object_ids(obj)
      object_ids = []
      objects = obj['tree']['_resolved']['children']
      objects.each { |object|
        # if nested hash
        if object['has_children']
          # send array of those hashes
          get_object_ids(object['children'],object_ids)
        else
          # not a nested hash
          object_ids << object['id']
        end
      }
      object_ids
    end

    # recursively iterating through
    # n nested levels of archival object hashes
    def get_object_ids(tree,ids)
      tree.each { |items|
        if items["has_children"]
          get_objects(items['children'],ids)
        else
          ids << items['id']
        end
      }
    end

    # get archival objects and top container tree
    def get_related_containers(related_objects)
      related_containers = []
      related_objects.each { |r|
        obj = resolve_references(ArchivalObject.to_jsonmodel(r),
        ['top_container'])
        related_containers << obj['instances']
      }
      related_containers
    end

    def get_top_container_id(url)
      info = url.split('/')[4]
      info.to_i
    end

    # returns a hash of top container metadata
    def get_top_container_metadata(data)
      tc_id = get_top_container_id(data['ref'])
      barcode =  data['_resolved']['barcode']
      hash = {id: tc_id, indicator: data['_resolved']['indicator'] }
      # if no barcode, just get indicator,
      # else, merge barcode with indicator in one hash
      metadata = barcode.nil? ? hash : hash.merge({ barcode: barcode })
    end

    def get_top_containers(related_containers)
      top_containers = {}
      related_containers.each{ |containers|
        containers.each{ |t|
          if t['sub_container']
            top_container_tree = t['sub_container']['top_container']
            tc_info = get_top_container_metadata(top_container_tree)
            top_containers[tc_info[:id]] = tc_info.reject!{ |k,v| k == :id }
          end
        }
      }
      top_containers
    end

    # location metadata
    def get_location_metadata(id)
      obj = resolve_references(TopContainer.to_jsonmodel(id),
      ['container_locations'])
      location = obj['container_locations'][0]
      location['_resolved']['building'] if location
    end

    def get_locations(top_containers)
      location = {}
      tc = top_containers.dup
      top_containers.each_key { |id|
        # if there's location information
        # continue processing
        building = get_location_metadata(id)
        if  building
          location = {location: building}
          tc[id] = top_containers[id].merge(location)
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

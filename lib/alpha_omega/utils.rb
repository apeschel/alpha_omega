require 'capistrano'

module AlphaOmega

  def self.what_branch (allowed = %w(production master develop))
    if ENV["BRANCH"]
      ENV["BRANCH"]
    elsif ENV["TAG"]
      ENV["TAG"]
    else
      current = `git branch`.split("\n").find {|b| b.split(" ")[0] == '*' } # use Grit
      if current
        star, branch_name = current.split(" ")
        branch_type, branch_feature = branch_name.split("/")
        if %w(feature hotfix).member?(branch_type)
          branch_name
        elsif !branch_feature && allowed.member?(branch_type)
          branch_type
        else
          puts "current branch must be #{allowed.join(', ')}, feature/xyz, or hotfix/xyz"
          abort
        end
      else
        puts "could not find a suitable branch"
        abort
      end
    end
  end

  def self.what_pods (node_home)
    pods = { 
      "default" => {
        "nodes_spec" => "#{node_home}/nodes/*.json",
        "node_suffix" => ""
      }
    }

    yield "default", pods["default"]

    this_host = Socket.gethostname.chomp.split(".")[0]
    this_node = JSON.load(File.read("#{node_home}/nodes/#{this_host}.json"))
    (this_node["pods"] || []).each do |pod_name|
      pods[pod_name] = { 
        "nodes_spec" => "#{node_home}/pods/#{pod_name}/*.json",
        "node_suffix" => ".#{pod_name}"
      }

      yield pod_name, pods[pod_name]
    end

    pods
  end

  def self.what_hosts (pod)
    # load all the nodes and define cap tasks
    nodes = {}

    Dir[pod["nodes_spec"]].each do |fname|
      node_name = File.basename(fname, ".json")

      node = JSON.parse(IO.read(fname))
      node["node_name"] = node_name
      node["pod_context"] = pod

      nodes[node_name] = node

      yield node_name, "#{node_name}#{pod["node_suffix"]}", node unless node["virtual"]
    end

    nodes

  end

  def self.what_groups (nodes)
    # generalize groups
    cap_groups = {}

    nodes.each do |node_name, node|
      remote_name = "#{node_name}#{node["pod_context"]["node_suffix"]}"
      (node["cap_group"] || []).each do |g|
        cap_groups[g] ||= {}
        cap_groups[g][remote_name] = node
      end
    end

    cap_groups.each do |group_name, nodes|
      yield group_name, nodes
    end

    cap_groups
  end

end


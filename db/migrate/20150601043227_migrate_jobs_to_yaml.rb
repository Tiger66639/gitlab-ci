# Migration tested on MySQL and PostgreSQL.
# Can be performed online without errors.
# This migration will loop through all projects and jobs, so it can take some time.

class MigrateJobsToYaml < ActiveRecord::Migration
  def up
    select_all("SELECT * FROM projects").each do |project|
      config = {}

      concatenate_expression = if ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
                                 "string_agg(tags.name, ',')"
                               else
                                 "GROUP_CONCAT(tags.name SEPARATOR ',')"
                               end

      sql = "SELECT j.*, #{concatenate_expression} tags
        FROM jobs j
          LEFT JOIN taggings tgs ON j.id = tgs.taggable_id AND tgs.taggable_type = 'Job'
          LEFT JOIN tags ON tgs.tag_id = tags.id
        WHERE project_id = #{project['id']}
          AND active = true
          AND job_type = 'parallel'
        GROUP BY j.id"

      # Create Jobs
      select_all(sql).each do |job|
        config[job["name"].to_s] = {
          script: job["commands"] && job["commands"].split("\n").map(&:strip),
          tags: job["tags"] && job["tags"].split(",").map(&:strip)
        }

        except = build_except_param(parse_boolean_value(job["build_branches"]), parse_boolean_value(job["build_tags"]))

        if except
          config[job["name"].to_s][:except] = except
        end
      end

      # Create Deploy Jobs
      select_all(sql.sub("parallel", 'deploy')).each do |job|
        config[job["name"].to_s] = {
          script: job["commands"] && job["commands"].split("\n").map(&:strip),
          type: "deploy",
          tags: job["tags"] && job["tags"].split(",").map(&:strip)
        }

        except = build_except_param(parse_boolean_value(job["build_branches"]), parse_boolean_value(job["build_tags"]))

        if except
          config[job["name"].to_s][:except] = except
        end
      end

      yaml_config = YAML.dump(config.deep_stringify_keys)

      yaml_config.sub!("---", "# This file is generated by GitLab CI")

      execute("UPDATE projects SET generated_yaml_config = '#{quote_string(yaml_config)}' WHERE projects.id = #{project["id"]}")
    end
  end

  def down

  end

  private

  def parse_boolean_value(value)
    [ true, 1, '1', 't', 'T', 'true', 'TRUE', 'on', 'ON' ].include?(value)
  end

  def build_except_param(branches, tags)
    unless branches
      return ["branches"]
    end

    unless tags
      return ["tags"]
    end

    false
  end
end

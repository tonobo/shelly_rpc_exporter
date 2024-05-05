require 'prometheus/client'
require 'prometheus/middleware/collector'
require 'prometheus/middleware/exporter'
require 'typhoeus'
require 'oj'
require 'sinatra'
require 'rack'

use Rack::Deflater

def rpc_json(target, method, id)
  id = id || 0
  raise "target must be given" if target.to_s.empty?

  response = Typhoeus.get("http://#{target}/rpc/#{method}?id=#{0}")
  raise "#{method} response failed for target: #{target}: #{response.inspect}" unless response.success?

  begin
    return [id, Oj.safe_load(response.body)]
  rescue StandardError => err
    raise "#{method} body load failed for target #{target}, invalid json: #{err}"
  end
end

get '/metrics/em' do
  id, body = rpc_json(params["target"], "EM.GetStatus", params["id"]) 

  metrics = []

  %w(a b c).each.with_index do |phase, index|
    {
      "current" => %Q(current_%%),
      "voltage" => %Q(voltage_%%),
      "act_power" => %Q(power_watts_%%),
      "aprt_power" => %Q(apparent_power_watts_%%),
      "pf" => %Q(power_factor_%%),
      "freq" => %Q(frequency_%%),
    }.each do |suffix, metric_template|
      original = "#{phase}_#{suffix}"
      metric_name = metric_template.gsub("%%", "l#{index+1}")
      value = body.fetch(original, 0)
      metrics << %(#TYPE shelly_rpc_em_#{metric_name} gauge)
      metrics << %(shelly_rpc_em_#{metric_name}{id="#{id}"} #{value.to_f}).strip
    end
  end

  {
    "total_current" => %Q(total_current),
    "total_act_power" => %Q(power_watts),
    "total_aprt_power" => %Q(apparent_power_watts),
  }.each do |original, metric_name|
    value = body.fetch(original, 0)
    metrics << %(#TYPE shelly_rpc_em_#{metric_name} gauge)
    metrics << %(shelly_rpc_em_#{metric_name}{id="#{id}"} #{value.to_f}).strip
  end


  headers 'Content-Type' => 'text/plain'

  metrics.join("\n") + "\n"
end

get '/metrics/emdata' do
  id, body = rpc_json(params["target"], "EMData.GetStatus", params["id"]) 

  metrics = []

  {
    "a_total_act_energy" => %Q(energy_consumed_l1_wh_total),
    "a_total_act_ret_energy" => %Q(energy_produced_l1_wh_total),
    "b_total_act_energy" => %Q(energy_consumed_l2_wh_total),
    "b_total_act_ret_energy" => %Q(energy_produced_l2_wh_total),
    "c_total_act_energy" => %Q(energy_consumed_l3_wh_total),
    "c_total_act_ret_energy" => %Q(energy_produced_l3_wh_total),
    "total_act" => %Q(energy_consumed_wh_total),
    "total_act_ret" => %Q(energy_produced_wh_total),
  }.each do |original, metric_name|
    value = body.fetch(original, 0)
    metrics << %(#TYPE shelly_rpc_emdata_#{metric_name} counter)
    metrics << %(shelly_rpc_emdata_#{metric_name}{id="#{id}"} #{value.to_f}).strip
  end

  headers 'Content-Type' => 'text/plain'

  metrics.join("\n") + "\n"
end

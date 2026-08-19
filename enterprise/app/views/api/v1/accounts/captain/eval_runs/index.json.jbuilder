json.data do
  json.array! @eval_runs, partial: 'eval_run', as: :eval_run
end

json.meta do
  json.current_page @eval_runs.current_page
  json.total_pages @eval_runs.total_pages
  json.total_count @eval_runs.total_count
end

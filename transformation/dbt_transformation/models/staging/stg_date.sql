SELECT
  d::DATE AS date,
  year(d) AS year,
  month(d) AS month,
  monthname(d) AS month_name,
  day(d) AS day,
  isodow(d) AS day_of_week,
  dayname(d) AS day_name,
  ((day(d) + isodow(date_trunc('month', d)) - 2) // 7) + 1 AS week_of_month
FROM
  generate_series(DATE '{{ var("start_date") }}', DATE '{{ var("end_date") }}', INTERVAL 1 DAY) AS t (d)
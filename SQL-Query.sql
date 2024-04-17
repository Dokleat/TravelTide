-- Determining the proportion of individuals (cohort) who had more than 7 sessions after January 4, 2023
WITH cohort AS (
  SELECT user_id
  FROM sessions
  WHERE session_start > '2023-01-04'
  GROUP BY user_id
  HAVING COUNT(session_id) > 7
),
-- Personalized data for each user, including statistics such as the number of sessions,
-- average session duration, number of trips, conversion and cancellation rates, etc.
custom_data AS (
  SELECT
    s.user_id,
    COUNT(DISTINCT s.session_id) AS session_count,
    ROUND(AVG(EXTRACT(MINUTE FROM (session_end - session_start))), 2) AS avg_session_duration,
    ROUND(AVG(page_clicks), 2) AS avg_page_clicks,
    COUNT(DISTINCT CASE WHEN NOT cancellation THEN s.trip_id END) AS total_trips,
    ROUND(AVG(CASE WHEN NOT cancellation THEN 1 ELSE 0 END), 2) AS conversion_rate,
    ROUND(AVG(CASE WHEN cancellation THEN 1 ELSE 0 END), 2) AS cancellation_proportion,
    COUNT(DISTINCT CASE WHEN flight_booked THEN s.trip_id END) AS total_flights_booked,
    ROUND(AVG(EXTRACT(EPOCH FROM (f.departure_time - s.session_end)) / 86400), 2) AS avg_days_until_departure,
    ROUND(AVG(EXTRACT(EPOCH FROM (h.check_in_time - s.session_end)) / 86400), 2) AS avg_days_until_checkin,
    ROUND(AVG(CASE WHEN flight_booked AND return_flight_booked THEN 1 ELSE 0 END), 2) AS round_trips_proportion,
    ROUND(AVG(f.base_fare_usd), 2) AS avg_flight_price_usd,
    ROUND(AVG(s.flight_discount_amount), 2) AS avg_flight_discount_amount,
    ROUND(AVG(CASE WHEN flight_discount THEN 1 ELSE 0 END), 2) AS discounted_flight_proportion,
    ROUND(AVG(f.seats), 2) AS avg_flight_seats,
    ROUND(AVG(f.checked_bags), 2) AS avg_checked_bags,
    COUNT(DISTINCT CASE WHEN hotel_booked THEN s.trip_id END) AS total_hotels_booked,
    ROUND(AVG(h.hotel_per_room_usd), 2) AS avg_hotel_price_usd,
    ROUND(AVG(s.hotel_discount_amount), 2) AS avg_hotel_discount_amount,
    ROUND(AVG(CASE WHEN hotel_discount THEN 1 ELSE 0 END), 2) AS discounted_hotel_proportion,
    ROUND(AVG(h.rooms), 2) AS avg_hotel_rooms,
    ROUND(AVG(EXTRACT(DAY from (h.check_out_time - h.check_in_time))), 2) AS avg_stay_duration_day,
    ROUND(CAST(AVG(haversine_distance(u.home_airport_lat, u.home_airport_lon, f.destination_airport_lat, f.destination_airport_lon)) AS numeric), 2) AS avg_flight_distance_from_home_km
  FROM sessions s
  LEFT JOIN flights f ON s.trip_id = f.trip_id
  LEFT JOIN hotels h ON s.trip_id = h.trip_id
  LEFT JOIN users u ON s.user_id = u.user_id
  WHERE s.user_id IN (SELECT user_id FROM cohort)
  GROUP BY s.user_id
),
-- Calculation of preferred benefits for each user based on their activity and travel preferences.
perks AS (
  SELECT
    cd.user_id,
    MAX(CASE
      WHEN cd.avg_hotel_rooms > cd.avg_flight_seats AND cd.total_hotels_booked > cd.total_flights_booked THEN 'free hotel meal'
      WHEN cd.avg_checked_bags > 1 THEN 'free checked bag'
      WHEN cd.cancellation_proportion > 0.1 THEN 'no cancellation fees'
      WHEN cd.discounted_flight_proportion > 0.5 OR cd.discounted_hotel_proportion > 0.5 THEN 'exclusive discounts'
      WHEN cd.total_flights_booked > 0 AND cd.total_hotels_booked > 0 THEN '1 night free hotel with flight'
      ELSE 'exclusive discounts'
    END) AS preferred_perk
  FROM custom_data cd
  GROUP BY cd.user_id
)
-- Obtaining completed data for each user, including personal details and calculated benefits.
SELECT
  u.user_id,
  u.sign_up_date,
  EXTRACT(YEAR from AGE(u.birthdate)) AS age,
  u.gender,
  u.married,
  u.has_children,
  u.home_country,
  u.home_city,
  cd.*,
  p.preferred_perk,
  (p.preferred_perk IS NOT NULL)::int AS perk_filter
FROM users u
JOIN custom_data cd ON u.user_id = cd.user_id
JOIN perks p ON u.user_id = p.user_id;
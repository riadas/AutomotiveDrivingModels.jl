export 
		get,
		get_unimplemented_indicators

type ExtractedFeatureCache
	dict :: Dict{(Int, Int, Symbol), Float64} # (carid, frameind, feature symbol) -> value
    ExtractedFeatureCache() = new(Dict{(Int, Int, Symbol), Float64}())
end
function Base.setindex!(cache::ExtractedFeatureCache, val::Float64, key::(Int, Int, Symbol)) 
	cache.dict[key] = val
end
function Base.getindex(cache::ExtractedFeatureCache, key::(Int, Int, Symbol)) 
	cache.dict[key]
end

# TODO(tim): should not use this in parallel because meta() is a single global value

unimplemented = false
clear_unimp() = global unimplemented = false

function  get(F::AbstractFeature, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	
	key = (carind, frameind, symbol(F))
	if haskey(cache.dict, key)
		return cache.dict[key]
	end

	value = _get(F, log, road, timestep, carind, frameind, cache)::Float64
	!isnan(value) || error("value from feature $(symbol(F)) was NaN!")

	cache.dict[key] = value

	value
end
function _get(F::AbstractFeature, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	warn(@sprintf("get not implemented for feature %s", string(symbol(F))))
	global unimplemented = true
	return NaN
end

# NOTE(tim):  get() is used for fast lookups
#            _get() is used for caching calculations
function get(F::Features.Feature_PosFx, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	
	log[frameind, calc_logindexbase(carind) + LOG_COL_X]
end
function get(F::Features.Feature_PosFy, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	
	log[frameind, calc_logindexbase(carind) + LOG_COL_Y]
end
function get(F::Features.Feature_Yaw, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	log[frameind, calc_logindexbase(carind) + LOG_COL_ϕ]
end
function get(F::Features.Feature_Speed, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	log[frameind, calc_logindexbase(carind) + LOG_COL_V]
end
function get(F::Features.Feature_Delta_Speed_Limit, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	log[frameind, calc_logindexbase(carind) + LOG_COL_V] - 29.06 # TODO(tim): make this less arbitrary?
end
function get(F::Features.Feature_VelFx, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	base = calc_logindexbase(carind)
	v = log[frameind, base + LOG_COL_V]
	ϕ = log[frameind, base + LOG_COL_ϕ]
	v * cos(ϕ)
end
function get(F::Features.Feature_VelFy, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	base = calc_logindexbase(carind)
	v = log[frameind, base + LOG_COL_V]
	ϕ = log[frameind, base + LOG_COL_ϕ]
	v * sin(ϕ)
end
function _get(F::Features.Feature_TurnRate, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	if frameind <= 1
		return NA_ALIAS
	end

	indϕ = calc_logindexbase(carind) + LOG_COL_ϕ
	curr = log[frameind, indϕ]
	past = log[frameind-1, indϕ]
	Features.deltaangle(curr, past) / timestep
end

function _get(F::Features.Feature_CL, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	posFy = get(POSFY, log, road, timestep, carind, frameind, cache)
	# generate the lane centerlines
	nlanes = road.nlanes
	lanewidth = road.lanewidth
	lane_centers = [0:(nlanes-1)].*lanewidth # [0,lw,2lw,...]
	float64(indmin(abs(lane_centers .- posFy)))
end
function _get(F::Features.Feature_D_CL, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	# y - cl_y
	lane = get(CL, log, road, timestep, carind, frameind, cache)
	posFy = get(POSFY, log, road, timestep, carind, frameind, cache)
	posFy - (lane-1)*road.lanewidth
end
function _get(F::Features.Feature_D_ML, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	d_cl = get(D_CL, log, road, timestep, carind, frameind, cache)
	if abs(d_cl) > 0.5road.lanewidth && d_cl > 0.0
		return NA_ALIAS
	end
	0.5road.lanewidth - d_cl
end
function _get(F::Features.Feature_D_MR, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	d_cl = get(D_CL, log, road, timestep, carind, frameind, cache)
	if abs(d_cl) > 0.5road.lanewidth && d_cl < 0.0
		return NA_ALIAS
	end
	0.5road.lanewidth + d_cl
end
function  get(::Features.Feature_TimeToCrossing_Left, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	d_ml = get(D_ML, log, road, timestep, carind, frameind, cache)
	velFy = get(VELFY, log, road, timestep, carind, frameind, cache)
	d_ml > 0.0 && velFy > 0.0 ? min(d_ml / velFy,Features.THRESHOLD_TIME_TO_CROSSING) : NA_ALIAS
end
function  get(::Features.Feature_TimeToCrossing_Right, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	d_mr = get(D_MR, log, road, timestep, carind, frameind, cache)
	velFy = get(VELFY, log, road, timestep, carind, frameind, cache)
	d_mr > 0.0 && velFy < 0.0 ? min(d_mr / velFy, Features.THRESHOLD_TIME_TO_CROSSING) : NA_ALIAS
end
function _get(::Features.Feature_EstimatedTimeToLaneCrossing, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	ttcr_left = get(TIMETOCROSSING_LEFT, log, road, timestep, carind, frameind, cache)
	if !isinf(ttcr_left)
		return ttcr_left
	end
	get(TIMETOCROSSING_RIGHT, log, road, timestep, carind, frameind, cache)
end
function get(::Features.Feature_TimeSinceLaneCrossing, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	
	lane_start = get(CL, log, road, timestep, carind, frameind, cache)

	cur_frameind = frameind

	for pastframeind = frameind - 1 : -1 : 1
		Δt = (frameind - pastframeind) * timestep
		if Δt > Features.THRESHOLD_TIMESINCELANECROSSING
			return Features.THRESHOLD_TIMESINCELANECROSSING
		end

		past_lane = get(CL, log, road, timestep, carind, frameind, cache)
		if past_lane != lane_start
			return Δt
		end
	end
	return Features.THRESHOLD_TIMESINCELANECROSSING
end
function get(F::Features.Feature_D_Merge, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	
	100.0 # NOTE(tim): make this less arbitrary - saturation point for StreetMap d_merge
end
function get(F::Features.Feature_D_Split, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	
	100.0 # NOTE(tim): make this less arbitrary - saturation point for StreetMap d_split
end

function _get(F::Features.Feature_N_LANE_L, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	lane = get(CL, log, road, timestep, carind, frameind, cache)
	float64(road.nlanes - lane)
end
function _get(F::Features.Feature_HAS_LANE_L, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	
	float64(_get(N_LANE_L, log, road, timestep, carind, frameind, cache) > 0.0)
end
function _get(F::Features.Feature_N_LANE_R, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	
	get(CL, log, road, timestep, carind, frameind, cache) - 1.0
end
function _get(F::Features.Feature_HAS_LANE_R, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	
	float64(_get(N_LANE_R, log, road, timestep, carind, frameind, cache) > 0.0)
end
function _get(F::Features.Feature_Acc, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	if frameind <= 1
		return 0.0
	end

	curr = get(SPEED, log, road, timestep, carind, frameind, cache)
	past = get(SPEED, log, road, timestep, carind, frameind-1, cache)
	(curr - past) / timestep
end
function _get(F::Features.Feature_AccFx, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	if frameind <= 1
		return 0.0
	end

	curr = get(VELFX, log, road, timestep, carind, frameind, cache)
	past = get(VELFX, log, road, timestep, carind, frameind-1, cache)
	(curr - past) / timestep
end
function _get(F::Features.Feature_AccFy, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	if frameind <= 1
		return 0.0
	end

	curr = get(VELFY, log, road, timestep, carind, frameind, cache)
	past = get(VELFY, log, road, timestep, carind, frameind-1, cache)
	(curr - past) / timestep
end

function get(::Features.Feature_A_REQ_StayInLane, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	velFy = get(VELFY, log, road, timestep, carind, frameind, cache)
	d_mr = get(D_MR, log, road, timestep, carind, frameind, cache)
	if d_mr > 0.0
		return -min(0.5velFy*velFy / d_mr, Features.THRESHOLD_A_REQ)
	end
	d_ml = get(D_ML, log, road, timestep, carind, frameind, cache)
	d_ml > 0.0 ?  -min(0.5velFy*velFy / d_ml, Features.THRESHOLD_A_REQ) : NA_ALIAS
end

# FRONT
	function _get(::Features.Feature_IndFront, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		
		base = calc_logindexbase(carind)
		mylane = get(CL, log, road, timestep, carind, frameind, cache)
		myFx = log[frameind, base+LOG_COL_X]
		myFy = log[frameind, base+LOG_COL_Y]

		frontcar_ind = 0
		frontcar_dist = Inf
		for i = 1 : get_ncars(log)
			if i == carind
				continue
			end

			base2 = calc_logindexbase(i)
			dy = abs(log[frameind, base2+LOG_COL_Y] - myFy)
			dlane = get(CL, log, road, timestep, i, frameind, cache) - mylane
			if isapprox(dlane, 0.0) || dy < Features.THRESHOLD_DY_CONSIDERED_IN_FRONT
				dx = log[frameind, base2+LOG_COL_X] - myFx
				if 0 < dx < frontcar_dist
					frontcar_dist, frontcar_ind = dx, i
				end
			end
		end

		if frontcar_ind != 0
			@assert(frontcar_ind != carind)

			# compute extra stats
			myϕ  = log[frameind, base+LOG_COL_ϕ]
			myv  = log[frameind, base+LOG_COL_V]
			myVx = myv * cos(myϕ)
			myVy = myv * sin(myϕ)

			base2 = calc_logindexbase(frontcar_ind)
			othFy = log[frameind, base2+LOG_COL_Y]
			othϕ  = log[frameind, base2+LOG_COL_ϕ]
			othv  = log[frameind, base2+LOG_COL_V]
			othVx = othv * cos(othϕ)
			othVy = othv * sin(othϕ)

			cache.dict[(carind, frameind, :has_front)] = 1.0
			cache.dict[(carind, frameind, :d_x_front)] = frontcar_dist
			cache.dict[(carind, frameind, :d_y_front)] = othFy - myFy
			cache.dict[(carind, frameind, :v_x_front)] = othVx - myVx
			cache.dict[(carind, frameind, :v_y_front)] = othVy - myVy
			return float64(frontcar_ind)
		end

		cache.dict[(carind, frameind, :has_front)] = 0.0
		cache.dict[(carind, frameind, :d_x_front)] = Features.NA_ALIAS
		cache.dict[(carind, frameind, :d_y_front)] = Features.NA_ALIAS
		cache.dict[(carind, frameind, :v_x_front)] = Features.NA_ALIAS
		cache.dict[(carind, frameind, :v_y_front)] = Features.NA_ALIAS
		return Features.NA_ALIAS
	end
	function _get(::Features.Feature_HAS_FRONT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDFRONT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :has_front)]
	end
	function _get(::Features.Feature_D_X_FRONT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDFRONT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :d_x_front)]
	end
	function _get(::Features.Feature_D_Y_FRONT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDFRONT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :d_y_front)]
	end
	function _get(::Features.Feature_V_X_FRONT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDFRONT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :v_x_front)]
	end
	function _get(::Features.Feature_V_Y_FRONT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDFRONT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :v_y_front)]
	end
	function _get(::Features.Feature_TTC_X_FRONT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	
		ind_front = get(INDFRONT, log, road, timestep, carind, frameind, cache)
		if ind_front == NA_ALIAS
			return NA_ALIAS
		end

		dx = get(D_X_FRONT, log, road, timestep, carind, frameind, cache) # distance between cars
		dv = get(V_X_FRONT, log, road, timestep, carind, frameind, cache) # v_front - v_back

		if dv >= 0.0 # they are pulling away; we are good
			return NA_ALIAS
		end

		min(-dx / dv, Features.THRESHOLD_TIME_TO_COLLISION)
	end
	function _get(::Features.Feature_A_REQ_FRONT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	
		ind_front = get(INDFRONT, log, road, timestep, carind, frameind, cache)
		if ind_front == NA_ALIAS
			return NA_ALIAS
		end

		dx = get(D_X_FRONT, log, road, timestep, carind, frameind, cache) # distance between cars
		dv = get(V_X_FRONT, log, road, timestep, carind, frameind, cache) # v_front - v_back

		if dv >= 0.0 # they are pulling away; we are good
			return NA_ALIAS
		end

		-min(dv*dv / (2dx), THRESHOLD_A_REQ)
	end
	function _get(::Features.Feature_TimeGap_X_FRONT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	
		ind_front = get(INDFRONT, log, road, timestep, carind, frameind, cache)
		if ind_front == NA_ALIAS
			return Features.THRESHOLD_TIMEGAP
		end

		dx = get(D_X_FRONT, log, road, timestep, carind, frameind, cache) # distance between cars
		 v = get(VELFX,     log, road, timestep, carind, frameind, cache)

		if v <= 0.0
			return Features.THRESHOLD_TIMEGAP
		end

		min(dx / v, Features.THRESHOLD_TIMEGAP)
	end

# REAR
	function _get(F::Features.Feature_IndRear, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		
		base = calc_logindexbase(carind)
		mylane = get(CL, log, road, timestep, carind, frameind, cache)
		myFx = log[frameind, base+LOG_COL_X]
		myFy = log[frameind, base+LOG_COL_Y]

		rearcar_ind = 0
		rearcar_dist = Inf
		for i = 1 : get_ncars(log)
			if i == carind
				continue
			end

			base2 = calc_logindexbase(i)
			dy = abs(log[frameind, base2+LOG_COL_Y] - myFy)
			dlane = get(CL, log, road, i, frameind, cache) - mylane
			if isapprox(dlane, 0.0) || dy < Features.THRESHOLD_DY_CONSIDERED_IN_REAR
				dx = log[frameind, base2+LOG_COL_X] - myFx
				if rearcar_dist < dx < 0
					rearcar_dist, rearcar_ind = dx, i
				end
			end
		end

		if rearcar_ind != 0
			@assert(rearcar_ind != carind)

			# compute extra stats
			myϕ  = log[frameind, base+LOG_COL_ϕ]
			myv  = log[frameind, base+LOG_COL_V]
			myVx = myv * cos(myϕ)
			myVy = myv * sin(myϕ)

			base2 = calc_logindexbase(rearcar_ind)
			othϕ = log[frameind, base2+LOG_COL_ϕ]
			othv = log[frameind, base2+LOG_COL_V]
			othVx = othv * cos(othϕ)
			othVy = othv * sin(othϕ)

			cache[(carind, frameind, :has_rear)] = 1.0
			cache[(carind, frameind, :d_x_rear)] = abs(rearcar_dist)
			cache[(carind, frameind, :v_x_rear)] = othVx - myVx
			cache[(carind, frameind, :v_y_rear)] = othVy - myVy
			return float64(rearcar_ind)
		end

		cache[(carind, frameind, :has_rear)] = 0.0
		cache[(carind, frameind, :d_x_rear)] = Features.NA_ALIAS
		cache[(carind, frameind, :v_x_rear)] = Features.NA_ALIAS
		cache[(carind, frameind, :v_y_rear)] = Features.NA_ALIAS
		return Features.NA_ALIAS
	end
	function _get(F::Features.Feature_HAS_REAR, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDREAR, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :has_rear)]
	end
	function _get(F::Features.Feature_D_X_REAR, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDREAR, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :d_x_rear)]
	end
	function _get(F::Features.Feature_V_X_REAR, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDREAR, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :v_x_rear)]
	end
	function _get(F::Features.Feature_V_Y_REAR, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDREAR, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :v_y_rear)]
	end
	function _get(::Features.Feature_TTC_X_REAR, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	
		ind_rear = get(INDREAR, log, road, timestep, carind, frameind, cache)
		if ind_rear == NA_ALIAS
			return NA_ALIAS
		end

		dx = get(D_X_FRONT, log, road, timestep, carind, frameind, cache) # distance between cars
		dv = get(V_X_FRONT, log, road, timestep, carind, frameind, cache) # v_front - v_back

		if dv <= 0.0
			return NA_ALIAS
		end

		if dv <= 0.0
			return NA_ALIAS
		end

		min(dx / dv, THRESHOLD_TIME_TO_COLLISION)
	end
	function _get( ::Features.Feature_A_REQ_REAR, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		
		ind_rear = get(INDREAR, log, road, timestep, carind, frameind, cache)
		if ind_rear == NA_ALIAS
			return NA_ALIAS
		end

		dx = get(D_X_REAR, log, road, timestep, carind, frameind, cache) # distance between cars
		dv = get(V_X_REAR, log, road, timestep, carind, frameind, cache) # v_rear - v_back

		if dv <= 0.0 # they are pulling away; we are good
			return NA_ALIAS
		end

		min(dv*dv / (2dx), THRESHOLD_A_REQ)
	end

# LEFT
	function _get(F::Features.Feature_IndLeft, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		
		base = calc_logindexbase(carind)
		mylane = get(CL, log, road, timestep, carind, frameind, cache)
		myFx = log[frameind, base+LOG_COL_X]
		myFy = log[frameind, base+LOG_COL_Y]
		myϕ  = log[frameind, base+LOG_COL_ϕ]
		myV  = log[frameind, base+LOG_COL_V]
		myVx = myV * cos(myϕ)
		myVy = myV * sin(myϕ)

		d_y_left = 0.0
		v_x_left = 0.0
		v_y_left = 0.0
		yaw_left = 0.0

		leftcar_ind = 0
		leftcar_dist = Inf
		for i = 1 : get_ncars(log)
			if i == carind
				continue
			end

			base2 = calc_logindexbase(i)
			dy = abs(log[frameind, base2+LOG_COL_Y] - myFy)
			their_lane = get(CL, log, road, i, frameind, cache) - mylane
			if isapprox(their_lane, mylane+1)
				dx = log[frameind, base2+LOG_COL_X] - myFx
				if abs(dx) < abs(leftcar_dist)
					leftcar_ind = i
					leftcar_dist = dx
					d_y_left = log[frameind, base2+LOG_COL_Y] - myFy
					v_left   = log[frameind, base2+LOG_COL_V]
					yaw_left = log[frameind, base2+LOG_COL_ϕ]
					v_x_left = v_left * cos(yaw_left) - myVx
					v_y_left = v_left * sin(yaw_left) - myVy
				end
			end
		end

		if leftcar_ind != 0
			@assert(leftcar_ind != carind)

			cache[(carind, frameind, :d_x_left)] = leftcar_dist
			cache[(carind, frameind, :d_y_left)] = d_y_left
			cache[(carind, frameind, :v_x_left)] = v_x_left
			cache[(carind, frameind, :v_y_left)] = v_y_left
			cache[(carind, frameind, :yaw_left)] = yaw_left
			return float64(leftcar_ind)
		end

		cache[(carind, frameind, :d_x_left)] = Features.NA_ALIAS
		cache[(carind, frameind, :d_y_left)] = Features.NA_ALIAS
		cache[(carind, frameind, :v_x_left)] = Features.NA_ALIAS
		cache[(carind, frameind, :v_y_left)] = Features.NA_ALIAS
		cache[(carind, frameind, :yaw_left)] = Features.NA_ALIAS
		return Features.NA_ALIAS
	end
	function _get(F::Features.Feature_D_X_LEFT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDLEFT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :d_x_left)]
	end
	function _get(F::Features.Feature_D_Y_LEFT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDLEFT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :d_y_left)]
	end
	function _get(F::Features.Feature_V_X_LEFT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDLEFT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :v_x_left)]
	end
	function _get(F::Features.Feature_V_Y_LEFT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDLEFT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :v_y_left)]
	end
	function _get(F::Features.Feature_YAW_LEFT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDLEFT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :yaw_left)]
	end

# RIGHT
	function _get(::Features.Feature_IndRight, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		
		base = calc_logindexbase(carind)
		mylane = get(CL, log, road, timestep, carind, frameind, cache)
		myFx = log[frameind, base+LOG_COL_X]
		myFy = log[frameind, base+LOG_COL_Y]
		myϕ  = log[frameind, base+LOG_COL_ϕ]
		myV  = log[frameind, base+LOG_COL_V]
		myVx = myV * cos(myϕ)
		myVy = myV * sin(myϕ)

		d_y_right = 0.0
		v_x_right = 0.0
		v_y_right = 0.0
		yaw_right = 0.0

		rightcar_ind = 0
		rightcar_dist = Inf
		for i = 1 : get_ncars(log)
			if i == carind
				continue
			end

			base2 = calc_logindexbase(i)
			dy = abs(log[frameind, base2+LOG_COL_Y] - myFy)
			their_lane = get(CL, log, road, i, frameind, cache) - mylane
			if isapprox(their_lane, mylane-1)
				dx = log[frameind, base2+LOG_COL_X] - myFx
				if abs(dx) < abs(rightcar_dist)
					rightcar_ind = i
					rightcar_dist = dx
					d_y_right = log[frameind, base2+LOG_COL_Y] - myFy
					v_right   = log[frameind, base2+LOG_COL_V]
					yaw_right = log[frameind, base2+LOG_COL_ϕ]
					v_x_right = v_right * cos(yaw_right) - myVx
					v_y_right = v_right * sin(yaw_right) - myVy
				end
			end
		end

		if rightcar_ind != 0
			@assert(rightcar_ind != carind)

			cache[(carind, frameind, :d_x_right)] = rightcar_dist
			cache[(carind, frameind, :d_y_right)] = d_y_right
			cache[(carind, frameind, :v_x_right)] = v_x_right
			cache[(carind, frameind, :v_y_right)] = v_y_right
			cache[(carind, frameind, :yaw_right)] = yaw_right
			return float64(rightcar_ind)
		end

		cache[(carind, frameind, :d_x_right)] = Features.NA_ALIAS
		cache[(carind, frameind, :d_y_right)] = Features.NA_ALIAS
		cache[(carind, frameind, :v_x_right)] = Features.NA_ALIAS
		cache[(carind, frameind, :v_y_right)] = Features.NA_ALIAS
		cache[(carind, frameind, :yaw_right)] = Features.NA_ALIAS
		return Features.NA_ALIAS
	end
	function _get(::Features.Feature_D_X_RIGHT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDRIGHT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :d_x_right)]
	end
	function _get(::Features.Feature_D_Y_RIGHT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDRIGHT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :d_y_right)]
	end
	function _get(::Features.Feature_V_X_RIGHT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDRIGHT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :v_x_right)]
	end
	function _get(::Features.Feature_V_Y_RIGHT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDRIGHT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :v_y_right)]
	end
	function _get(::Features.Feature_YAW_RIGHT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDRIGHT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :yaw_right)]
	end
	function _get(::Features.Feature_A_REQ_RIGHT, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
		get(INDRIGHT, log, road, timestep, carind, frameind, cache)
		cache[(carind, frameind, :yaw_right)]
		
		ind_right = get(INDRIGHT, log, road, timestep, carind, frameind, cache)
		if ind_right == NA_ALIAS
			return NA_ALIAS
		end

		dx = get(D_X_RIGHT, log, road, timestep, carind, frameind, cache) # distance between cars
		dv = get(V_X_RIGHT, log, road, timestep, carind, frameind, cache) # v_other - v_me

		if (dx > 0.0 && dv > 0.0) || (dx < 0.0 && dv < 0.0)
			return NA_ALIAS
		end

		min(dv*dv / (2*abs(dx)), Features.THRESHOLD_A_REQ)
	end

function get_past_feature(F::AbstractFeature, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, ms_past::Int, cache::ExtractedFeatureCache)

	frames_back = convert(Int, ceil(ms_past / timestep))

	if frameind+1 <= frames_back
		frames_back = frameind - 2
	end	

	get(F, log, road, timestep, carind, frameind-frames_back, cache)
end
get(::Features.Feature_PastTurnrate250ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(TURNRATE, log, road, timestep, carind, frameind, 250, cache)
get(::Features.Feature_PastTurnrate500ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(TURNRATE, log, road, timestep, carind, frameind, 500, cache)
get(::Features.Feature_PastTurnrate750ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(TURNRATE, log, road, timestep, carind, frameind, 750, cache)
get(::Features.Feature_PastTurnrate1s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(TURNRATE, log, road, timestep, carind, frameind, 1000, cache)

get(::Features.Feature_PastAcc250ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(ACC, log, road, timestep, carind, frameind,  250, cache)
get(::Features.Feature_PastAcc500ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(ACC, log, road, timestep, carind, frameind,  500, cache)
get(::Features.Feature_PastAcc750ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(ACC, log, road, timestep, carind, frameind,  750, cache)
get(::Features.Feature_PastAcc1s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(ACC, log, road, timestep, carind, frameind, 1000, cache)

get(::Features.Feature_PastVelFy250ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(VELFY, log, road, timestep, carind, frameind,  250, cache)
get(::Features.Feature_PastVelFy500ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(VELFY, log, road, timestep, carind, frameind,  500, cache)
get(::Features.Feature_PastVelFy750ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(VELFY, log, road, timestep, carind, frameind,  750, cache)
get(::Features.Feature_PastVelFy1s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(VELFY, log, road, timestep, carind, frameind, 1000, cache)

get(::Features.Feature_PastD_CL250ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(D_CL, log, road, timestep, carind, frameind,  250, cache)
get(::Features.Feature_PastD_CL500ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(D_CL, log, road, timestep, carind, frameind,  500, cache)
get(::Features.Feature_PastD_CL750ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(D_CL, log, road, timestep, carind, frameind,  750, cache)
get(::Features.Feature_PastD_CL1s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_past_feature(D_CL, log, road, timestep, carind, frameind, 1000, cache)

function _get(::Features.Feature_Time_Consecutive_Brake, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	# scan backward until the car is no longer braking
	# NOTE(tim): returns positive time values

	const THRESHOLD_BRAKING = -0.05 # [m/s²]

	if frameind == 1
		cache[(carind, frameind, :time_consecutive_accel)] = 0.0
		return 0.0
	end

	cur_accel = get(ACC, log, road, timestep, carind, frameind, cache)
	if cur_accel > THRESHOLD_BRAKING
		return 0.0
	end

	cache[(carind, frameind, :time_consecutive_accel)] = 0.0

	past_frameind = frameind
	done = false
	while !done
		past_frameind -= 1
		if past_frameind > 1
			past_accel = get(ACC, log, road, timestep, carind, past_frameind, cache)
			if past_accel > THRESHOLD_BRAKING
				return timestep * (frameind - past_frameind - 1)
			end

			Δt = timestep * (frameind - past_frameind)
			if Δt > Features.THRESHOLD_TIMECONSECUTIVEACCEL
				return Features.THRESHOLD_TIMECONSECUTIVEACCEL
			end
		else
			return timestep * (frameind - past_frameind - 1)
		end
	end

	error("INVALID CODEPATH")
	return 0.0
end
function _get(::Features.Feature_Time_Consecutive_Accel, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	# scan backward until the car is no longer braking
	# NOTE(tim): returns positive time values

	const THRESHOLD_ACCELERATION = 0.05 # [m/s²]

	if frameind == 1
		cache[(carind, frameind, :time_consecutive_brake)] = 0.0
		return 0.0 # default
	end

	cur_accel = get(ACC, log, road, timestep, carind, frameind, cache)
	if cur_accel < THRESHOLD_ACCELERATION
		return 0.0
	end

	cache[(carind, frameind, :time_consecutive_brake)] = 0.0

	past_frameind = frameind
	done = false
	while !done
		past_frameind -= 1
		if past_frameind > 1

			past_accel = get(ACC, log, road, timestep, carind, past_frameind, cache)
			if past_accel < THRESHOLD_ACCELERATION
				return timestep * (frameind - past_frameind - 1)
			end

			Δt = timestep * (frameind - past_frameind)
			if Δt > Features.THRESHOLD_TIMECONSECUTIVEACCEL
				return Features.THRESHOLD_TIMECONSECUTIVEACCEL
			end
		else
			return timestep * (frameind - past_frameind - 1)
		end
	end

	error("INVALID CODEPATH")
	return 0.0
end
function _get(::Features.Feature_Time_Consecutive_Throttle, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache)
	t_consec_accel = get(TIME_CONSECUTIVE_ACCEL, log, road, timestep, carind, frameind, cache)
	if t_consec_accel > 0
		return t_consec_accel
	end
	-get(TIME_CONSECUTIVE_BRAKE, log, road, timestep, carind, frameind, cache)
end

function get_max_accFx(log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, ms_past::Int, cache::ExtractedFeatureCache)

	frames_back = convert(Int, ceil(ms_past / timestep))

	if frameind <= frames_back
		frames_back = frameind-1
	end	

	indϕ = calc_logindexbase(carind) + LOG_COL_ϕ
	retval = 0.0
	val = get(VELFX, log, road, timestep, carind, frameind, cache)
	for i = 1 : frames_back
		val2 = get(VELFX, log, road, timestep, carind, frameind-i, cache)
		accFx = (val2 - val) / timestep
		if abs(accFx) > retval
			retval = accFx
		end
		val = val2
	end
	
	retval
end
get(::Features.Feature_MaxAccFx250ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFx(log, road, timestep, carind, frameind, 250, cache)
get(::Features.Feature_MaxAccFx500ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFx(log, road, timestep, carind, frameind, 500, cache)
get(::Features.Feature_MaxAccFx750ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFx(log, road, timestep, carind, frameind, 750, cache)
get(::Features.Feature_MaxAccFx1s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFx(log, road, timestep, carind, frameind, 1000, cache)
get(::Features.Feature_MaxAccFx1500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFx(log, road, timestep, carind, frameind, 1500, cache)
get(::Features.Feature_MaxAccFx2s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFx(log, road, timestep, carind, frameind, 2000, cache)
get(::Features.Feature_MaxAccFx2500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFx(log, road, timestep, carind, frameind, 2500, cache)
get(::Features.Feature_MaxAccFx3s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFx(log, road, timestep, carind, frameind, 3000, cache)
get(::Features.Feature_MaxAccFx4s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFx(log, road, timestep, carind, frameind, 4000, cache)

function get_max_accFy(log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, ms_past::Int, cache::ExtractedFeatureCache)

	frames_back = convert(Int, ceil(ms_past / timestep))

	if frameind <= frames_back
		frames_back = frameind - 1
	end	

	indϕ = calc_logindexbase(carind) + LOG_COL_ϕ
	retval = 0.0
	val = get(VELFY, log, road, timestep, carind, frameind, cache)
	for i = 1 : frames_back
		val2 = get(VELFY, log, road, timestep, carind, frameind-i, cache)
		accFy = (val2 - val) / timestep
		if abs(accFy) > retval
			retval = accFy
		end
		val = val2
	end
	
	retval
end
get(::Features.Feature_MaxAccFy250ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFy(log, road, timestep, carind, frameind, 250, cache)
get(::Features.Feature_MaxAccFy500ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFy(log, road, timestep, carind, frameind, 500, cache)
get(::Features.Feature_MaxAccFy750ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFy(log, road, timestep, carind, frameind, 750, cache)
get(::Features.Feature_MaxAccFy1s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFy(log, road, timestep, carind, frameind, 1000, cache)
get(::Features.Feature_MaxAccFy1500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFy(log, road, timestep, carind, frameind, 1500, cache)
get(::Features.Feature_MaxAccFy2s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFy(log, road, timestep, carind, frameind, 2000, cache)
get(::Features.Feature_MaxAccFy2500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFy(log, road, timestep, carind, frameind, 2500, cache)
get(::Features.Feature_MaxAccFy3s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFy(log, road, timestep, carind, frameind, 3000, cache)
get(::Features.Feature_MaxAccFy4s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_accFy(log, road, timestep, carind, frameind, 4000, cache)


function get_max_turnrate(log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, ms_past::Int, cache::ExtractedFeatureCache)

	frames_back = convert(Int, ceil(ms_past / timestep))

	if frameind <= frames_back
		frames_back = frameind - 1
	end	

	indϕ = calc_logindexbase(carind) + LOG_COL_ϕ
	retval = 0.0
	val = log[frameind, indϕ]
	for i = 1 : frames_back
		val2 = log[frameind-i, indϕ]
		turnrate = Features.deltaangle(val, val2) / timestep
		if abs(turnrate) > retval
			retval = turnrate
		end
		val = val2
	end
	
	retval
end
get(::Features.Feature_MaxTurnRate250ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_turnrate(log, road, timestep, carind, frameind, 250, cache)
get(::Features.Feature_MaxTurnRate500ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_turnrate(log, road, timestep, carind, frameind, 500, cache)
get(::Features.Feature_MaxTurnRate750ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_turnrate(log, road, timestep, carind, frameind, 750, cache)
get(::Features.Feature_MaxTurnRate1s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_turnrate(log, road, timestep, carind, frameind, 1000, cache)
get(::Features.Feature_MaxTurnRate1500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_turnrate(log, road, timestep, carind, frameind, 1500, cache)
get(::Features.Feature_MaxTurnRate2s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_turnrate(log, road, timestep, carind, frameind, 2000, cache)
get(::Features.Feature_MaxTurnRate2500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_turnrate(log, road, timestep, carind, frameind, 2500, cache)
get(::Features.Feature_MaxTurnRate3s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_turnrate(log, road, timestep, carind, frameind, 3000, cache)
get(::Features.Feature_MaxTurnRate4s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_max_turnrate(log, road, timestep, carind, frameind, 4000, cache)

function get_mean_accFx(log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, ms_past::Int, cache::ExtractedFeatureCache)

	frames_back = convert(Int, ceil(ms_past / timestep))

	if frameind+1 <= frames_back
		frames_back = frameind-2
	end	

	retval = 0.0
	val = get(VELFX, log, road, timestep, carind, frameind, cache)
	for i = 1 : frames_back
		val2 = get(VELFX, log, road, timestep, carind, frameind-i, cache)
		retval += (val2 - val) / timestep
		val = val2
	end
	
	retval / frames_back
end
get(::Features.Feature_MeanAccFx250ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFx(log, road, timestep, carind, frameind, 250, cache)
get(::Features.Feature_MeanAccFx500ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFx(log, road, timestep, carind, frameind, 500, cache)
get(::Features.Feature_MeanAccFx750ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFx(log, road, timestep, carind, frameind, 750, cache)
get(::Features.Feature_MeanAccFx1s, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFx(log, road, timestep, carind, frameind, 1000, cache)
get(::Features.Feature_MeanAccFx1500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFx(log, road, timestep, carind, frameind, 1500, cache)
get(::Features.Feature_MeanAccFx2s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFx(log, road, timestep, carind, frameind, 2000, cache)
get(::Features.Feature_MeanAccFx2500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFx(log, road, timestep, carind, frameind, 2500, cache)
get(::Features.Feature_MeanAccFx3s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFx(log, road, timestep, carind, frameind, 3000, cache)
get(::Features.Feature_MeanAccFx4s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFx(log, road, timestep, carind, frameind, 4000, cache)

function get_mean_accFy(log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, ms_past::Int, cache::ExtractedFeatureCache)

	frames_back = convert(Int, ceil(ms_past / timestep))

	if frameind+1 <= frames_back
		frames_back = frameind-2
	end	

	retval = 0.0
	val = get(VELFY, log, road, timestep, carind, frameind, cache)
	for i = 1 : frames_back
		val2 = get(VELFY, log, road, timestep, carind, frameind-i, cache)
		retval += (val2 - val) / timestep
		val = val2
	end
	
	retval / frames_back
end
get(::Features.Feature_MeanAccFy250ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFy(log, road, timestep, carind, frameind, 250, cache)
get(::Features.Feature_MeanAccFy500ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFy(log, road, timestep, carind, frameind, 500, cache)
get(::Features.Feature_MeanAccFy750ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFy(log, road, timestep, carind, frameind, 750, cache)
get(::Features.Feature_MeanAccFy1s, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFy(log, road, timestep, carind, frameind, 1000, cache)
get(::Features.Feature_MeanAccFy1500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFy(log, road, timestep, carind, frameind, 1500, cache)
get(::Features.Feature_MeanAccFy2s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFy(log, road, timestep, carind, frameind, 2000, cache)
get(::Features.Feature_MeanAccFy2500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFy(log, road, timestep, carind, frameind, 2500, cache)
get(::Features.Feature_MeanAccFy3s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFy(log, road, timestep, carind, frameind, 3000, cache)
get(::Features.Feature_MeanAccFy4s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_accFy(log, road, timestep, carind, frameind, 4000, cache)

function get_mean_turnrate(log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, ms_past::Int, cache::ExtractedFeatureCache)

	frames_back = convert(Int, ceil(ms_past / timestep))

	if frameind+1 <= frames_back
		frames_back = frameind-1
	end

	indϕ = calc_logindexbase(carind) + LOG_COL_ϕ
	retval = 0.0
	val = log[frameind, indϕ]
	for i = 1 : frames_back
		val2 = log[frameind-i, indϕ]
		retval += Features.deltaangle(val, val2) / timestep
		val = val2
	end
	
	retval / frames_back
end
get(::Features.Feature_MeanTurnRate250ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_turnrate(log, road, timestep, carind, frameind, 250, cache)
get(::Features.Feature_MeanTurnRate500ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_turnrate(log, road, timestep, carind, frameind, 500, cache)
get(::Features.Feature_MeanTurnRate750ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_turnrate(log, road, timestep, carind, frameind, 750, cache)
get(::Features.Feature_MeanTurnRate1s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_turnrate(log, road, timestep, carind, frameind, 1000, cache)
get(::Features.Feature_MeanTurnRate1500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_turnrate(log, road, timestep, carind, frameind, 1500, cache)
get(::Features.Feature_MeanTurnRate2s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_turnrate(log, road, timestep, carind, frameind, 2000, cache)
get(::Features.Feature_MeanTurnRate2500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_turnrate(log, road, timestep, carind, frameind, 2500, cache)
get(::Features.Feature_MeanTurnRate3s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_turnrate(log, road, timestep, carind, frameind, 3000, cache)
get(::Features.Feature_MeanTurnRate4s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_mean_turnrate(log, road, timestep, carind, frameind, 4000, cache)

function _get_std_feature(arr::Vector{Float64}, nan_return_value::Float64 = 0.0)
	retval = std(arr)
	if isnan(retval)
		return nan_return_value
	end
	retval
end
function get_std_accFx(log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, ms_past::Int, cache::ExtractedFeatureCache)

	frames_back = convert(Int, ceil(ms_past / timestep))

	if frameind+1 <= frames_back
		frames_back = frameind-1
	end

	if frames_back < 2
		return 0.0
	end

	retval = 0.0
	arr = zeros(Float64, frames_back)
	val = get(VELFX, log, road, timestep, carind, frameind, cache)
	for i = 1 : frames_back
		val2 = get(VELFX, log, road, timestep, carind, frameind-i, cache)
		arr[i] = (val2 - val) / timestep
		val = val2
	end
	
	_get_std_feature(arr)
end
get(::Features.Feature_StdAccFx250ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFx(log, road, timestep, carind, frameind, 250, cache)
get(::Features.Feature_StdAccFx500ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFx(log, road, timestep, carind, frameind, 500, cache)
get(::Features.Feature_StdAccFx750ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFx(log, road, timestep, carind, frameind, 750, cache)
get(::Features.Feature_StdAccFx1s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFx(log, road, timestep, carind, frameind, 1000, cache)
get(::Features.Feature_StdAccFx1500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFx(log, road, timestep, carind, frameind, 1500, cache)
get(::Features.Feature_StdAccFx2s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFx(log, road, timestep, carind, frameind, 2000, cache)
get(::Features.Feature_StdAccFx2500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFx(log, road, timestep, carind, frameind, 2500, cache)
get(::Features.Feature_StdAccFx3s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFx(log, road, timestep, carind, frameind, 3000, cache)
get(::Features.Feature_StdAccFx4s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFx(log, road, timestep, carind, frameind, 4000, cache)

function get_std_accFy(log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, ms_past::Int, cache::ExtractedFeatureCache)
	
	frames_back = convert(Int, ceil(ms_past / timestep))

	if frameind+1 <= frames_back
		frames_back = frameind-1
	end	

	if frames_back < 2
		return 0.0
	end

	retval = 0.0
	arr = zeros(Float64, frames_back)
	val = get(VELFY, log, road, timestep, carind, frameind, cache)
	for i = 1 : frames_back
		val2 = get(VELFY, log, road, timestep, carind, frameind-i, cache)
		arr[i] = (val2 - val) / timestep
		val = val2
	end
	
	_get_std_feature(arr)
end
get(::Features.Feature_StdAccFy250ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFy(log, road, timestep, carind, frameind, 250, cache)
get(::Features.Feature_StdAccFy500ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFy(log, road, timestep, carind, frameind, 500, cache)
get(::Features.Feature_StdAccFy750ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFy(log, road, timestep, carind, frameind, 750, cache)
get(::Features.Feature_StdAccFy1s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFy(log, road, timestep, carind, frameind, 1000, cache)
get(::Features.Feature_StdAccFy1500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFy(log, road, timestep, carind, frameind, 1500, cache)
get(::Features.Feature_StdAccFy2s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFy(log, road, timestep, carind, frameind, 2000, cache)
get(::Features.Feature_StdAccFy2500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFy(log, road, timestep, carind, frameind, 2500, cache)
get(::Features.Feature_StdAccFy3s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFy(log, road, timestep, carind, frameind, 3000, cache)
get(::Features.Feature_StdAccFy4s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_accFy(log, road, timestep, carind, frameind, 4000, cache)


function get_std_turnrate(log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, ms_past::Int, cache::ExtractedFeatureCache)

	frames_back = convert(Int, ceil(ms_past / timestep))

	if frameind+1 <= frames_back
		frames_back = frameind-1
	end	

	if frames_back < 2
		return 0.0
	end

	indϕ = calc_logindexbase(carind) + LOG_COL_ϕ
	retval = 0.0
	arr = zeros(Float64, frames_back)
	val = get(TURNRATE, log, road, timestep, carind, frameind, cache)
	for i = 1 : frames_back
		val2 = get(TURNRATE, log, road, timestep, carind, frameind-i, cache)
		arr[i] = (val2 - val) / timestep
		val = val2
	end
	
	_get_std_feature(arr)
end
get(::Features.Feature_StdTurnRate250ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_turnrate(log, road, timestep, carind, frameind, 250, cache)
get(::Features.Feature_StdTurnRate500ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_turnrate(log, road, timestep, carind, frameind, 500, cache)
get(::Features.Feature_StdTurnRate750ms, log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_turnrate(log, road, timestep, carind, frameind, 750, cache)
get(::Features.Feature_StdTurnRate1s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_turnrate(log, road, timestep, carind, frameind, 1000, cache)
get(::Features.Feature_StdTurnRate1500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_turnrate(log, road, timestep, carind, frameind, 1500, cache)
get(::Features.Feature_StdTurnRate2s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_turnrate(log, road, timestep, carind, frameind, 2000, cache)
get(::Features.Feature_StdTurnRate2500ms,log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_turnrate(log, road, timestep, carind, frameind, 2500, cache)
get(::Features.Feature_StdTurnRate3s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_turnrate(log, road, timestep, carind, frameind, 3000, cache)
get(::Features.Feature_StdTurnRate4s,    log::Matrix{Float64}, road::StraightRoadway, timestep::Float64, carind::Int, frameind::Int, cache::ExtractedFeatureCache) =
	get_std_turnrate(log, road, timestep, carind, frameind, 4000, cache)


#####

function get_unimplemented_indicators(em::EM)

    runlog = create_log(1,1)
    road   = StraightRoadway(1,1.0)

    unimplemented = AbstractFeature[]
    for f in get_indicators(em)
        clear_unimp()
        get(f, runlog, road, 1.0, 1, 1)
        if unimplemented
            push!(unimplemented, f)
        end
    end
    unimplemented
end
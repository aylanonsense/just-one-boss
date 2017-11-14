pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
--[[
coordinates:
  +x is right, -x is left
  +y is towards the player, -y is away from the player
  +z is up, -z is down
           x=1   x=2.5
            v     v
          +---+---+
    y=1 > |   |   | < r=1
          +---+---+
          |   |   |
  y=2.5 > +---+---+ < r=2
            ^     ^
           c=1   c=2

hurtbox_channels:
	1: player
]]

-- useful noop function
function noop() end

-- global constants
local num_cols=8
local num_rows=5
local color_ramps={
	{7,13,5,1,0,0,0,0},
	{7,14,8,2,1,0,0,0},
	{7,6,11,3,5,1,0,0},
	{7,15,9,4,2,1,0,0},
	{7,6,13,5,1,0,0,0},
	{7,7,7,6,13,5,1,0},
	{7,7,7,7,6,13,1,0},
	{7,7,14,8,2,1,0,0},
	{7,7,15,9,4,2,1,0},
	{7,7,15,10,9,4,1,0},
	{7,7,6,11,3,5,1,0},
	{7,7,6,12,13,5,1,0},
	{7,7,6,13,5,1,0,0},
	{7,7,15,14,8,2,1,0},
	{7,7,7,15,9,4,1,0}
}
color_ramps[0]={7,5,1,0,0,0,0,0}
local mirrored_directions={
	left="right",
	right="left",
	up="up",
	down="down"
}

-- global scene vars
local scenes
local scene
local scene_frame
local freeze_frames
local screen_shake_frames
local next_scene
local transition_frames_left

-- global input vars
local buttons
local button_presses

-- global tile vars
local tiles
local levels={
	"xxxxxxxx"..
	"xxxxxxxx"..
	"xxxxxxxx"..
	"xxxxxxxx"..
	"xxxxxxxx"
}

-- global entity vars
local player
local entities
local new_entities
local entity_classes={
	player={
		hurtbox_channel=1,
		facing="right",
		move_dir=nil,
		next_move_dir=nil,
		move_frames=0,
		prev_col=nil,
		prev_row=nil,
		horizontal_move_increments={1,2,3,4},
		vertical_move_increments={1,2,2,3},
		teeter_frames=0,
		stun_frames=0,
		primary_color=12,
		secondary_color=13,
		eye_color=0,
		update=function(self)
			decrement_counter_prop(self,"stun_frames")
			if decrement_counter_prop(self,"teeter_frames") and self.next_move_dir then
				self:move(self.next_move_dir)
				self.next_move_dir=nil
			end
			-- try moving
			if button_presses[0] then
				self:queue_move("left")
			elseif button_presses[1] then
				self:queue_move("right")
			elseif button_presses[2] then
				self:queue_move("up")
			elseif button_presses[3] then
				self:queue_move("down")
			end
			-- actually move
			self.vx=0
			self.vy=0
			if self.stun_frames<=0 and self.teeter_frames<=0 and self.move_frames>0 then
				if self:step() then
					self.move_dir=nil
					if self.next_move_dir then
						self:move(self.next_move_dir)
						self.next_move_dir=nil
						self:step()
					end
				end
			end
			self.prev_col=self:col()
			self.prev_row=self:row()
			self:apply_velocity()
			if not tile_exists(self:col(),self:row()) and tile_exists(self.prev_col,self.prev_row) then
				self:cancel_move(self.prev_col,self.prev_row)
				self.teeter_frames=11
			end
		end,
		cancel_move=function(self,col,row)
			self.x=10*col-5
			self.y=8*row-4
			self.move_dir=nil
			self.move_frames=0
			self.next_move_dir=nil
		end,
		queue_move=function(self,dir)
			if not self.move_dir and self.teeter_frames<=0 then
				self:move(dir)
			else
				self.next_move_dir=dir
			end
		end,
		move=function(self,dir)
			self.facing=dir
			self.move_dir=dir
			self.move_frames=#self.horizontal_move_increments
		end,
		step=function(self)
			local dist
			if self.move_dir=="left" or self.move_dir=="right" then
				dist=self.horizontal_move_increments[self.move_frames]
			else
				dist=self.vertical_move_increments[self.move_frames]
			end
			local move_x,move_y=dir_to_vector(self.move_dir,dist)
			self.vx+=move_x
			self.vy+=move_y
			return decrement_counter_prop(self,"move_frames")
		end,
		on_hurt=function(self)
			self:stun()
			freeze_frames=max(freeze_frames,4)
			screen_shake_frames=max(screen_shake_frames,12)
		end,
		stun=function(self)
			-- self:cancel_move(self:col(),self:row())
			self.invincibility_frames=60
			self.stun_frames=19
		end,
		draw=function(self)
			local x=self.x
			local y=self.y
			local sprite_x=0
			local sprite_y=0
			local sprite_dx=3
			local sprite_dy=6
			local sprite_width=7
			local sprite_height=8
			local sprite_flipped=(self.facing=="left")
			if self.facing=="up" then
				sprite_y=8
				sprite_height=11
			elseif self.facing=="down" then
				sprite_y=19
				sprite_dy=9
				sprite_height=11
			end
			if self.stun_frames>0 then
				sprite_flipped=(self.frames_alive%8<4)
				sprite_dx=5
				sprite_dy=8
				sprite_width=11
				sprite_height=10
				sprite_x=64
				sprite_y=20
			elseif self.invincibility_frames%4>2 then
				return	
			elseif self.teeter_frames>0 then
				sprite_x=ternary(self.teeter_frames<=2,52,40)
				sprite_width=12
				if self.facing=="up" then
					sprite_dx=6
					sprite_dy+=3
				elseif self.facing=="down" then
					sprite_dx=6
					sprite_dy-=2
				else
					sprite_dx+=ternary(sprite_flipped,5,0)
				end
				local f=self.teeter_frames%4<2
				palt(ternary(f,8,9),true)
				pal(ternary(f,9,8),self.secondary_color)
			elseif self.move_frames>0 then
				sprite_x+=40-11*self.move_frames
				sprite_dx+=ternary(sprite_flipped,0,4)
				sprite_width+=4
			end
			pal(12,self.primary_color)
		pal(13,self.secondary_color)
			pal(1,self.eye_color)
			sspr(sprite_x,sprite_y,sprite_width,sprite_height,x-sprite_dx,y-sprite_dy,sprite_width,sprite_height,sprite_flipped)
			-- rect(left,top,right,bottom,8)
		end
	},
	player_reflection={
		extends="player",
		update_priority=10,
		primary_color=11,
		secondary_color=3,
		eye_color=3,
		update=function(self)
			self:copy_player()
		end,
		copy_player=function(self)
			self.x=80-player.x
			self.y=player.y
			self.facing=mirrored_directions[player.facing]
			self.move_dir=ternary(player.move_dir,mirrored_directions[player.move_dir],nil)
			self.move_frames=player.move_frames
			self.teeter_frames=player.teeter_frames
			self.stun_frames=player.stun_frames
			self.invincibility_frames=player.invincibility_frames
		end,
		on_hurt=function(self,entity)
			player:on_hurt(entity)
			self:copy_player()
		end,
	},
	heart={
		draw=function(self)
			palt(11,true)
			if (self.frames_alive+4)%30<20 then
				pal(14,8)
			end
			sspr(ternary(self.frames_alive%30<20,114,121),0,7,6,self.x-3,self.y-5)
		end
	},
	hourglass={
		hitbox_channel=1, --player
		frames_to_death=89,
		vx=1,
		check_for_hits=function(self,entity)
			return self:col()==entity:col() and self:row()==entity:row()
		end,
		draw=function(self)
			palt(11,true)
			local f=flr(self.frames_alive/2.5)%4
			if self.vx>0 then
				f=(4-f)%4
			end
			sspr(7+9*f,85,9,9,self.x-4,self.y-ternary(f==0,7,9))
			-- pset(self.x,self.y,8)
		end
	},
	cosmonas={
		init=function(self)
			self.head=spawn_entity("cosmonas_head",{x=5,y=-10})
			self.left_hand=spawn_entity("cosmonas_hand",{x=self.x,y=self.y,dir=1})
			self.right_hand=spawn_entity("cosmonas_hand",{x=self.x,y=self.y,dir=-1})

			self.head:fire_laser()

			self.left_hand:move_to(-10,4-8,10)
			self.left_hand:translate(0,16,30)
			self.left_hand:fire_hourglass()
			self.left_hand:translate(0,16,30)
			self.left_hand:fire_hourglass()

			self.right_hand:move_to(90,4,10)
			self.right_hand:fire_hourglass()
			self.right_hand:translate(0,16,30)
			self.right_hand:fire_hourglass()
			self.right_hand:translate(0,16,30)
			self.right_hand:fire_hourglass()
		end
	},
	cosmonas_head={
		vx=1,
		hitbox_channel=1, -- player
		laser_frames=0,
		jaw_open=0,
		init=function(self)
			self.future_state_data={}
		end,
		update=function(self)
			if self.state=="move" then
				self:apply_velocity()
				if self.x<=5 then
					self.vx=1
				elseif self.x>=75 then
					self.vx=-1
				end
			end
			if self.state=="open_jaw" and self.state_frames%5==0 then
				self.jaw_open+=1
			elseif self.state=="close_jaw" and self.state_frames%5==0 then
				self.jaw_open-=1
			elseif self.state=="charge_laser" and self.state_frames%2==0 then
				local r=rnd_int(-170,-10)
				spawn_entity("spark",{x=self.x+20*cos(r/360),y=self.y+20*sin(r/360),target_x=self.x,target_y=self.y,color=14})
			end
		end,
		draw=function(self)
			palt(11,true)
			-- draw skull
			sspr(0,68,7,19,self.x-6,self.y-16)
			sspr(0,68,7,19,self.x,self.y-16,7,19,true)
			-- draw jaw
			sspr(2,87,5,6,self.x-4,self.y+self.jaw_open-3)
			sspr(2,87,5,6,self.x,self.y+self.jaw_open-3,5,6,true)
			-- draw laser
			if self.state=="laser_preview" and self.state_frames%2==0 then
				line(self.x,self.y+4,self.x,self.y+60,14)
			elseif self.state=="laser" then
				sspr(21,68,5,6,self.x-4,self.y+1)
				sspr(21,68,5,6,self.x,self.y+1,5,6,true)
				sspr(21,74,5,1,self.x-4,self.y+7,5,100)
				sspr(21,74,5,1,self.x,self.y+7,5,100,true)
			end
		end,
		check_for_hits=function(self,entity)
			return self.state=="laser" and entity:col()==self:col()
		end,
		on_no_state=function(self)
			self:queue_state("move",29)
			self:fire_laser()
		end,
		fire_laser=function(self)
			self:queue_state("open_jaw",14)
			self:queue_state("charge_laser",16)
			self:queue_state("pause",12)
			self:queue_state("laser_preview",8)
			self:queue_state("laser",35)
			self:queue_state("laser_preview",2)
			self:queue_state("pause",14)
			self:queue_state("close_jaw",14)
			self:queue_state("pause",12)
		end
	},
	cosmonas_hand={
		update=function(self)
			if self.state=="charge_up" and self.state_frames%2==0 then
				local r=rnd_int(140,210)
				spawn_entity("spark",{x=self.x-self.dir*20*cos(r/360),y=self.y+20*sin(r/360),target_x=self.x,target_y=self.y,color=10})
			elseif self.state=="move" then
				self.vx=(self.state_data.x-self.x)/(1+self.state_end-self.state_frames)
				self.vy=(self.state_data.y-self.y)/(1+self.state_end-self.state_frames)
				self:apply_velocity()
			end
		end,
		draw=function(self)
			palt(11,true)
			if self.dir>0 then
				sspr(7,68,14,17,self.x-8,self.y-8)
			else
				sspr(7,68,14,17,self.x-5,self.y-8,14,17,true)
			end
		end,
		on_enter_state=function(self)
			if self.state=="translate" then
				self.state="move"
				self.state_data.x+=self.x
				self.state_data.y+=self.y
			elseif self.state=="poof" then
				spawn_entity("poof",{x=self.x+self.dir*4,y=self.y})
			elseif self.state=="hourglass" then
				spawn_entity("hourglass",{x=self.x+self.dir*4,y=self.y,vx=self.dir})
			end
		end,
		move_to=function(self,x,y,dur)
			self:queue_state("move",dur,{x=x,y=y})
		end,
		translate=function(self,dx,dy,dur)
			self:queue_state("translate",dur,{x=dx,y=dy})
		end,
		fire_hourglass=function(self)
			self:queue_state("charge_up",14)
			self:queue_state("pause",10)
			self:queue_state("poof",3)
			self:queue_state("hourglass",3)
		end
	},
	spark={
		color=8,
		frames_to_death=15,
		percent=0,
		update=function(self)
			self.percent=mid(0,self.percent+0.02+0.15*self.percent,1)
		end,
		draw=function(self)
			local x,y=self.x,self.y
			local dx,dy=self.target_x-x,self.target_y-y
			local x2,y2=x+self.percent*dx,y+self.percent*dy
			color(color_ramps[self.color][mid(1,6-flr(self.frames_alive/3),6)])
			pset(x2,y2)
		end
	},
	poof={
		frames_to_death=16,
		draw=function(self)
			palt(11,true)
			sspr(13*flr(self.frames_alive/4),94,13,14,self.x-7,self.y-7)
		end
	},
	comet={
		color=7,
		frames_to_death=30,
		init=function(self)
			self.locs={}
		end,
		update=function(self)
			local dx=self.target_x-self.x
			local dy=self.target_y-self.y
			local dist=sqrt(dx*dx+dy*dy)
			if dist>0 then
				local acc=mid(0.2,self.frames_alive/2-2,4)
				self.vx+=acc*dx/dist
				self.vy+=acc*dy/dist
			end
			self.vx*=0.8
			self.vy*=0.8
			self:apply_velocity()
			if self.y>self.target_y-5 and self.frames_to_death>2 then
				self.x=self.target_x
				self.y=self.target_y
				self.frames_to_death=2
			end
			add(self.locs,self.x)
			add(self.locs,self.y)
		end,
		draw=function(self)
			for i=max(1,#self.locs-7),#self.locs-2,2 do
				line(self.locs[i],self.locs[i+1],self.locs[i+2],self.locs[i+3],self.color)
			end
		end,
		on_death=function(self)
			spawn_entity("splosion",{x=self.target_x,y=self.target_y})
		end
	},
	splosion={
		frames_to_death=10,
		draw=function(self)
			sspr(40+16*flr(self.frames_alive/2),48,16,16,self.x-7,self.y-8)
			-- pset(self.x,self.y,8)
		end
	}
}


-- primary pico-8 functions (_init, _update, _draw)
function _init()
	freeze_frames=0
	transition_frames_left=0
	screen_shake_frames=0
	buttons={}
	button_presses={}
	init_scene("game")
end

local skip_frames=0
function _update()
	skip_frames=increment_counter(skip_frames)
	if skip_frames%1>0 then return end
	-- keep track of inputs (because btnp repeats presses)
	local i
	for i=0,5 do
		button_presses[i]=btn(i) and not buttons[i]
		buttons[i]=btn(i)
	end
	-- transition between scenes
	if transition_frames_left>0 then
		transition_frames_left=decrement_counter(transition_frames_left)
		if transition_frames_left==30 then
			init_scene(next_scene)
			next_scene=nil
		end
	end
	-- call the update function of the current scene
	if freeze_frames>0 then
		freeze_frames=decrement_counter(freeze_frames)
	else
		screen_shake_frames=decrement_counter(screen_shake_frames)
		scene_frame=increment_counter(scene_frame)
		scenes[scene][2]()
	end
end

function _draw()
	-- reset the canvas
	camera()
	rectfill(0,0,127,127,0)
	-- draw guidelines
	rect(0,0,63,63,1)
	rect(66,0,127,63,1)
	rect(0,66,63,127,1)
	rect(66,66,127,127,1)
	-- call the draw function of the current scene
	scenes[scene][3]()
	-- draw the scene transition
	camera()
	if transition_frames_left>0 then
		local t,x,y=transition_frames_left
		if t<30 then
			t+=30
		end
		for y=0,128,6 do
			for x=0,128,6 do
				local size=mid(0,50-t+y/10-x/40,4)
				if transition_frames_left<30 then
					size=4-size
				end
				if size>0 then
					circfill(x,y,size,0)
				end
			end
		end
	end
end


-- game functions
function init_game()
	-- reset everything
	entities,new_entities={},{}
	-- create initial entities
	player=spawn_entity("player",{x=10*3+5,y=8*2+4})
	spawn_entity("player_reflection",{x=10*4+5,y=8*2+4})
	spawn_entity("cosmonas",{x=40,y=-44})
	spawn_entity("heart",{x=10*5+5,y=8*3+4})
	spawn_entity("poof",{x=10*7+5,y=8*3+4})
	-- spawn_entity("hourglass",{x=10*8+5,y=8*0+4,vx=-1})
	-- spawn_entity("hourglass",{x=10*8+5,y=8*2+4,vx=-1})
	-- spawn_entity("hourglass",{x=10*8+5,y=8*4+4,vx=-1})
	-- spawn_entity("hourglass",{x=10*-1+5,y=8*1+4})
	-- spawn_entity("hourglass",{x=10*-1+5,y=8*3+4})
	-- create tiles
	create_tiles(levels[1])
	-- immediately add new entities to the game
	add_new_entities()
end

function update_game()
	-- sort entities for updating
	sort_list(entities,updates_before)
	-- update entities
	local entity
	for entity in all(entities) do
		-- stateful entities will transition between various states
		increment_counter_prop(entity,"state_frames")
		entity:check_for_state_change()
		-- call the entity's update function
		entity:update()
		-- do some default update stuff
		decrement_counter_prop(entity,"invincibility_frames")
		increment_counter_prop(entity,"frames_alive")
		if decrement_counter_prop(entity,"frames_to_death") then
			entity:die()
		end
	end
	-- if scene_frame%7==0 then
	-- 	spawn_entity("comet",{color=rnd_from_list({14}),x=40,y=-30,target_x=5+10*rnd_int(0,7),target_y=4+8*rnd_int(0,4),vx=rnd_int(-3,3),vy=rnd_int(-5,-4)})
	-- end
	-- check for hits
	local i,j,entity,entity2
	for i=1,#entities do
		entity=entities[i]
		for j=1,#entities do
			entity2=entities[j]
			if i!=j and band(entity.hitbox_channel,entity2.hurtbox_channel)>0 and entity:check_for_hits(entity2) and entity2.invincibility_frames<=0 and entity:on_hit(entity2)!=false then
				entity2:on_hurt(entity)
			end
		end
	end
	-- add new entities to the game
	add_new_entities()
	-- remove dead entities from the game
	remove_deceased_entities(entities)
	-- sort entities for rendering
	sort_list(entities,renders_on_top_of)
end

function updates_before(entity1,entity2)
	return entity1.update_priority>entity2.update_priority
end

function renders_on_top_of(entity1,entity2)
	return entity1.render_layer>entity2.render_layer
end

function draw_game()
	local shake_x=0
	if freeze_frames<=0 and screen_shake_frames>0 then
		shake_x+=mid(1,screen_shake_frames/3,2)*(2*(scene_frame%2)-1)
	end
	camera(5*num_cols-65+shake_x,4*num_rows-96)
	local r,c
	for c=1,num_cols do
		for r=1,num_rows do
			if tiles[c][r] then
				sspr(0,ternary((c+r)%2==0,30,39),11,9,10*c-10,8*r-8)
			end
		end
	end
	line(1,-1,79,-1,1)
	line(-1,1,-1,40,1)
	line(81,1,81,40,1)
	palt(11,true)
	sspr(114,32,14,12,-1,41)
	sspr(114,32,14,12,68,41,14,12,true)
	local x
	for x=13,65,4 do
		sspr(124,32,4,12,x,41)
	end
	-- draw each entity
	pal()
	foreach(entities,function(entity)
		entity:draw()
		pal()
		-- pset(entity.x,entity.y,8)
	end)
	-- draw color ramps
	-- camera()
	-- local i,j
	-- for i=0,#color_ramps do
	-- 	for j=1,#color_ramps[i] do
	-- 		rectfill(3*j,3*i,3*j+2,3*i+2,color_ramps[i][j])
	-- 	end
	-- end
end


-- entity functions
function spawn_entity(class_name,args,skip_init)
	local super_class_name=entity_classes[class_name].extends
	local k,v
	local entity
	if super_class_name then
		entity=spawn_entity(super_class_name,args,true)
	else
		-- create default entity
		entity={
			is_alive=true,
			frames_alive=0,
			frames_to_death=0,
			render_layer=5,
			update_priority=5,
			-- hit props
			hitbox_channel=0,
			hurtbox_channel=0,
			invincibility_frames=0,
			-- state props
			state=nil,
			future_state_data={},
			state_frames=0,
			state_end=-1,
			state_data=nil,
			-- spatial props
			x=0,
			y=0,
			z=0,
			vx=0,
			vy=0,
			vz=0,
			-- entity methods
			add_to_game=noop,
			init=noop,
			update=function(self)
				self:apply_velocity()
			end,
			draw=noop,
			on_death=noop,
			on_collide=noop,
			col=function(self)
				return 1+flr(self.x/10)
			end,
			row=function(self)
				return 1+flr(self.y/8)
			end,
			die=function(self)
				self:on_death()
				self.is_alive=false
			end,
			apply_velocity=function(self)
				self.x+=self.vx
				self.y+=self.vy
				self.z+=self.vz
			end,
			-- hit methods
			check_for_hits=noop,
			on_hit=noop,
			on_hurt=noop,
			-- state methods
			queue_state=function(self,state,state_end,state_data)
				add(self.future_state_data,state)
				add(self.future_state_data,state_end or -1)
				add(self.future_state_data,state_data or false)
			end,
			queue_states=function(self,states)
				local i
				for i=1,#states,3 do
					self:queue_state(states[i],states[i+1],states[i+2])
				end
			end,
			on_enter_state=noop,
			on_no_state=noop,
			check_for_state_change=function(self)
				if (self.state and self.state_end>=0 and self.state_frames>self.state_end) or (not self.state and #self.future_state_data>0) then
					self.state=nil
					self.state_frames=0
					self.state_data=nil
					self.state_end=-1
					if #self.future_state_data>0 then
						self.state=remove_first(self.future_state_data)
						self.state_end=remove_first(self.future_state_data)
						self.state_data=remove_first(self.future_state_data)
						self:on_enter_state(self.state)
						if self.state_end==0 then
							self:check_for_state_change()
						end
					else
						self:on_no_state()
					end
				end
			end
		}
	end
	-- add class properties/methods onto it
	for k,v in pairs(entity_classes[class_name]) do
		if super_class_name and type(entity[k])=="function" then
			entity["super_"..k]=entity[k]
		end
		entity[k]=v
	end
	-- add properties onto it from the arguments
	for k,v in pairs(args or {}) do
		entity[k]=v
	end
	if not skip_init then
		-- initialize it
		entity:init(args or {})
		-- add it to the list of entities-to-be-added
		add(new_entities,entity)
	end
	-- return it
	return entity
end

function add_new_entities()
	foreach(new_entities,function(entity)
		entity:add_to_game()
		add(entities,entity)
	end)
	new_entities={}
end

function remove_deceased_entities(list)
	filter_list(list,function(entity)
		return entity.is_alive
	end)
end


-- tile functions
function create_tiles(level_def)
	tiles={}
	local c,r
	for c=1,num_cols do
		tiles[c]={}
		for r=1,num_rows do
			local i=c+(r-1)*num_cols
			local s=char_at(level_def,i)
			if s==" " then
				tiles[c][r]=false
			else
				tiles[c][r]={}
			end
		end
	end
end

function tile_exists(col,row)
	return tiles[col] and tiles[col][row]
end


-- scene functions
function init_scene(s)
	scene,scene_frame=s,0
	scenes[scene][1]()
end

function transition_to_scene(s)
	if next_scene!=s then
		next_scene=s
		transition_frames_left=60
	end
end


-- helper functions
function pal2(c1,c2)
	pal(c1,c2)
	palt(c1,c2==0)
end

function dir_to_vector(dir,magnitude)
	magnitude=magnitude or 1
	if dir=="left" then
		return -magnitude,0
	elseif dir=="right" then
		return magnitude,0
	elseif dir=="up" then
		return 0,-magnitude
	elseif dir=="down" then
		return 0,magnitude
	else
		return 0,0
	end
end

function ceil(n)
	return -flr(-n)
end

-- if condition is true return the second argument, otherwise the third
function ternary(condition,if_true,if_false)
	return condition and if_true or if_false
end

-- gets the character in string s at position n
function char_at(s,n)
	return sub(s,n,n)
end

-- removes and returns the first element of a list, operates in-place
function remove_first(list)
	local last=nil
	for i=#list,1,-1 do
		list[i],last=last,list[i]
	end
	return last
end

-- gets the first position of character c in string s
function char_index(s,c)
	local i
	for i=1,#s do
		if char_at(s,i)==c then
			return i
		end
	end
end

function rnd_from_list(list)
	return list[rnd_int(1,#list)]
end

-- generates a random integer between min_val and max_val, inclusive
function rnd_int(min_val,max_val)
	return flr(min_val+rnd(1+max_val-min_val))
end

-- if n is below min, wrap to max. if n is above max, wrap to min
function wrap(min_val,n,max_val)
	return ternary(n<min_val,max_val,ternary(n>max_val,min_val,n))
end

-- increment a counter, wrapping to 20000 if it risks overflowing
function increment_counter(n)
	if n>32000 then
		return 20000
	end
	return n+1
end

-- increment_counter on a property on an object
function increment_counter_prop(obj,k)
	obj[k]=increment_counter(obj[k])
end

-- decrement a counter but not below 0
function decrement_counter(n)
	return max(0,n-1)
end

-- decrement_counter on a property of an object, returns true when it reaches 0
function decrement_counter_prop(obj,k)
	if obj[k]>0 then
		obj[k]=decrement_counter(obj[k])
		return obj[k]<=0
	end
	return false
end

-- sorts list (inefficiently) based on func
function sort_list(list,func)
	local i
	for i=1,#list do
		local j=i
		while j>1 and func(list[j-1],list[j]) do
			list[j],list[j-1]=list[j-1],list[j]
			j-=1
		end
	end
end

-- filters list to contain only entries where func is truthy
function filter_list(list,func)
	local num_deleted,i=0
	for i=1,#list do
		if not func(list[i]) then
			list[i]=nil
			num_deleted+=1
		else
			list[i-num_deleted],list[i]=list[i],nil
		end
	end
end

-- set up the scenes now that the functions are defined
scenes={
	game={init_game,update_game,draw_game}
}


__gfx__
0ccccc00cc00000000000000cccc000000ccccc00000900cc00000000000000000000000000000000000000000000000000000000000000000b88b88bbb888bb
cccccccccccccccc0000000cccccc0000ccccccc00008dccccc0000000000000000000000000000000000000000000000000000000000000008888ee8b8888eb
cccc1c1cccc1111c1c0000ccc11c10000cccc1c100000cccccc00000c11cccc0000000000000000000000000000000000000000000000000008888ee8b8888eb
cdcc1c1cddd1111c1c00cddcc11c10000dccc1c10000dcc1c1cc00ccc11111cc00000000000000000000000000000000000000000000000000b88888bb88888b
cccccccccccccccccc000cccccccc0000ccccccc000ddcc1c1cc0dccddcccccc00000000000000000000000000000000000000000000000000b08880bb08880b
ddcccccddcdddd00000000ddccddc0000ddcccdc0000ddccccc0dddccccccdd000000000000000000000000000000000000000000000000000bbb8bbbbbb8bbb
ddddddddddd0000000000ddddddd0000dddddddd00000ddcccd0dddddddd00000000000000000000000000000000000000000000000000000000000000000000
0d000d00d00000000000000000d00000000000d0000000d00098000000d000000000000000000000000000000000000000000000000000000000000000000000
0ccccc00000000c00000000ccccc000000ccccc00000ccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000
ccccccc000000ccc0000000ccccc00000ccccccc090ccccccc090000000000000000000000000000000000000000000000000000000000000000000000000000
ccccccc000000ccc000000ccccccc0000ccccccc00dcccccccd000d0000000d00000000000000000000000000000000000000000000000000000000000000000
dcccccd000000ccc000000ccccccc0000dcccccd080cdddddc0800dcccccccd00000000000000000000000000000000000000000000000000000000000000000
ccccccc00000ccccc00000dcccccd0000ccccccc000ddddddd0000dcccccccd00000000000000000000000000000000000000000000000000000000000000000
cdddddc00000dcccd00000dcdddcd0000cdddddc000ddddddd0000cdddddddc00000000000000000000000000000000000000000000000000000000000000000
ddddddd00000dcccd00000ddddddd0000ddddddd0000ddddd00000ddddddddd00000000000000000000000000000000000000000000000000000000000000000
0d000d000000cdddc00000ddddddd00000000d0000000d000000000ddddddd000000000000000000000000000000000000000000000000000000000000000000
00000000000ddddddd0000000ddd0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000ddddddd00000000d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000d000d000000000d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000ccccc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000ccccccc0000000c000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000
00000000000cc1c1cc000000cc0c0000000000000000000000000000000000000000c0c000000000000000000000000000000000000000000000000000000000
0ccccc000000c1c1c000000ccccc000000ccccc000000000000000000ccc0000000ccccc00000000000000000000000000000000000000000000000000000000
ccccccc00000c1c1d00000cc1c1cc0000ccccccc0000ccccc0000000c1c1c000d0ccccccc0000000000000000000000000000000000000000000000000000000
cc1c1cc00000c1c1d00000cc1c1cd0000cc1c1cc090ccccccc080000c1c1c0000dcccc11c0d00000000000000000000000000000000000000000000000000000
dc1c1cd00000d1c1d00000cd1c1cd0000cc1c1cd00dcccccccd000ddc1c1cd000ccc1c11cd000000000000000000000000000000000000000000000000000000
ccccccc00000ddccc00000ddccccc0000cdccccc080ccccccc0900dcc1c1cdd0000ccccccc000000000000000000000000000000000000000000000000000000
dcccccd000000ddd000000dcccccc0000dcccccc000cc1c1cc0000ccc1c1ccd00dcccccc00000000000000000000000000000000000000000000000000000000
ddddddd000000ddd000000ddddddd0000ddddddd000cc1c1cc0000ccc1c1ccc000ddddddd0000000000000000000000000000000000000000000000000000000
0d000d00000000d00000000d0000000000d000000000ccccc0000000dddddd00000d000d00000000000000000000000000000000000000000000000000000000
51111111115eeeeeeeeeee2222222222200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11555555511e000000000e2000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
15511111551e000000000e2000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000011111111111111
15111511151e000000000e200000000020000000000000000000000000000000000000000000000000000000000000000000000000000000001100000000000b
15115551151e000000000e2000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000010110000111111
15111511151e000000000e2000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000010110011110101
15511111551e000000000e200000000020000000000000000000000000000000000000000000000000000000000000000000000000000000001100111110101b
11555555511e000000000e20000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000b1111111010101
51111111115eeeeeeeeeee22222222222000000000000000000000000000000000000000000000000000000000000000000000000000000000b000111010101b
5111111111522222222222eeeeeeeeeee000000000000000000000000000000000000000000000000000000000000000000000000000000000b0001101010101
1155555551120000000002e000000000e000000000000000000000000000000000000000000000000000000000000000000000000000000000b000101000100b
1551111155120000000002e000000000e000000000000000000000000000000000000000000000000000000000000000000000000000000000b000110000000b
1511151115120000000002e000000000e000000000000000000000000000000000000000000000000000000000000000000000000000000000b000100000000b
1511515115120000000002e000000000e000000000000000000000000000000000000000000000000000000000000000000000000000000000bbbb1bbbbbbbbb
1511151115120000000002e000000000e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1551111155120000000002e000000000e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1155555551120000000002e000000000e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
5111111111522222222222eeeeeeeeeee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
22222222222eeeeeeeeeee2222222222200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
20000000002e000000000e2000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
20000000002e000000000e2000000000200000000000000000000000000000000000000000000000000000000000000f00000000000000020000000000000000
20000000002e000000000e20000000002000000000000000000000000000000000000000000700070007000000fe000e000ef000002000000000200000000000
20000000002e000000000e2000000000200000000000000000000000000000000000000000007007007000000000000000000000000000000000000000000000
20000000002e000000000e2000000000200000000000000000000000000007070700000000770f0f0f0770000fe000000000ef00020000000000020000000000
20000000002e000000000e20000000002000000000000077700000000000707f707000000000f00000f000000000000000000000000000000000000000000000
20000000002e000000000e2000000000200000000000077777000000000007fff70000000000000e000000000000000000000000000000000000000000000000
22222222222eeeeeeeeeee222222222220000000000007777700000000077fffff770000077f00eee00f77000e00000000000e00000000000000000000000000
000000000000000000000000000000000000000000000777770000000000007f700000000000000e00000000f0000000000000f0200000000000002000000000
00000000000000000000000000000000000000000000000000000000000007070700000000000f000f0000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000007000000000000700f007000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000007000700070000000e0000000e0000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000700000000000f000e000f0000000200000002000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f00000000000000020000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbbb777bbbbbbbb7bbbbbbbeee000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b077777b000000770000bbefff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b777777b000000df0000bef777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b777777b000007f00000bef777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7777777b000007720000bef777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7777777b00000dd22000bef777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7777dd7b00777d7d2000bef777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7771177b07d7d777d200b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7722177b77f00d77fd00b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7d2277777d077dd7fd00b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
f77777177007f0dd0dd0b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bdff711f007df07707f0b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b0dd71db0077007f07dfb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b0d17dfb007d007d0077b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b0d17f7b007700777007700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b0d1717b00700007d000b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b001111bbbbbbbbb77bbb00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
b001111bb99999bbbbb9bbbbbbbbbbbbbbbbbbb9bbb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbb1111b0700070bb0907000bb0000000bb0007f90b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00dbbbbb0700070bb9007000b977000779b0007ff9b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000
007000bb007f700b90007000b900707ff9b0007fff90000000000000000000000000000000000000000000000000000000000000000000000000000000000000
007000bb0007000bb777f777b900f7fff9b777f777b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00f7171b007f700bb0007fff9900707ff990007000b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00b7777b07fff70bb0007ff9b977000779b9007000b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00bffffb07fff70bb0007f90bb0000000bb0907000b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000bb99999bbbbbbb9bbbbbbbbbbbbbbb9bbbbb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000
bbbbbbbbbbbbbbbbbbb7bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb0000000000000000000000000000000000000000000000000000000000000000000000000000
b00000700000bb00000000000bb00000000000bb00000000000b0000000000000000000000000000000000000000000000000000000000000000000000000000
b00000700000b700000000000bb000000000077b0000000000070000000000000000000000000000000000000000000000000000000000000000000000000000
b77000000000bb000000000777b000000000077b00000000000b0000000000000000000000000000000000000000000000000000000000000000000000000000
b00770077700bb000000007777b00000000070bb07000000000b0000000000000000000000000000000000000000000000000000000000000000000000000000
b00000077770bb00700000777bb07700070000bb00000000000b0000000000000000000000000000000000000000000000000000000000000000000000000000
b00007777770bb07770070000bb07700000000bb00000000000b0000000000000000000000000000000000000000000000000000000000000000000000000000
b00077777000bb07770000000bb00000000000bb00000000000b0000000000000000000000000000000000000000000000000000000000000000000000000000
b00077777000bb00700007700bb00000007000bb00000000000b0000000000000000000000000000000000000000000000000000000000000000000000000000
b00007770070bb00000077700bb00000000770bb00000000007b0000000000000000000000000000000000000000000000000000000000000000000000000000
b00000000007bb00000007700bb00000000770bb00000000000b0000000000000000000000000000000000000000000000000000000000000000000000000000
b00000007000bb000000000007b00000000000bb00000000000b0000000000000000000000000000000000000000000000000000000000000000000000000000
b00000007000bb00000000000bb00000000000bb00000000000b0000000000000000000000000000000000000000000000000000000000000000000000000000
bbbbbbbbbbbbbbbbbbbbb7bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb0000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01230000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
45670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
89ab0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cdef0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

__gff__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
010600003063030630306302463024620246202f0002f0002d0002d0052d0002d00500000000002d0002d0002b0002b0052b0002b00500000000002b0002b0002a0002a0002a0002a000300002f0002d0002b000
01060000215502b5512b5512b5412b5310d5012900026000215002b5012b5012b5012b5012b50128000240002900024000280000000000000000000000000000000000000000000000000000000000000002d000
0106000021120211151d1201d1152d000280002d0002f000300002f0002d0002b000290002800000000000000000000000000000000000000000000000000000000000000000000000000000000000000002f000
010300001c7301c730186043060524600182001830018300184001840018500185001860018600187001870018200182000000000000000000000000000000000000000000000000000000000000000000000000
010300001873018730000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0106000024540245302b5202b54013630136111360100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01060000186701865018620247702b7702b7700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010c0000185551c5551f5501f55000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010600000c2200c2210c2110c21100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000003065024631186210c61100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344


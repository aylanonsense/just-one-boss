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
	2: pickup
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
local rainbow={14,8,9,10,11,12}

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
	movable={
		apply_move=function(self)
			if self.state=="move" then
				local prev_x,prev_y=self.x,self.y
				local next_x,next_y=self.state_data.move(self.state_data.easing(self.state_frames/self.state_end))
				self.vx,self.vy=next_x-prev_x,next_y-prev_y
			end
			return self.state=="move"
		end,
		on_enter_move_state=function(self)
			local start_x,start_y=self.x,self.y
			local data=self.state_data
			local end_x,end_y=data.x,data.y
			-- if type(end_x)=="function" then
			-- 	end_x=end_x()
			-- end
			-- if type(end_y)=="function" then
			-- 	end_y=end_y()
			-- end
			if data.relative then
				end_x+=start_x
				end_y+=start_y
			end
			local dx,dy=end_x-start_x,end_y-start_y
			-- local dist=sqrt(dx*dx+dy*dy)
			local anchor_x1=data.anchors[1] or dx/4
			local anchor_y1=data.anchors[2] or dy/4
			local anchor_x2=data.anchors[3] or -dx/4
			local anchor_y2=data.anchors[4] or -dy/4
			self.state_data={
				final_x=end_x,
				final_y=end_y,
				easing=data.easing,
				move=make_bezier(
					start_x,start_y,
					start_x+anchor_x1,start_y+anchor_y1,
					end_x+anchor_x2,end_y+anchor_y2,
					end_x,end_y)
			}
		end,
		on_enter_state=function(self)
			if self.state=="move" then
				self:on_enter_move_state()
			end
			return self.state=="move"
		end,
		on_leave_state=function(self)
			if self.state=="move" then
				self.vx=0
				self.vy=0
				-- these can probably be removed:
				self.x=self.state_data.final_x
				self.y=self.state_data.final_y
			end
			return self.state=="move"
		end,
		move=function(self,x,y,dur,props)
			-- is_relative,easing,anchor_x1,anchor_y1,anchor_x2,anchor_y2
			-- x,y: where to move to
			-- dur: the number of frames the move should take
			-- props: an object of the following optional properties:
			--   relative: movement is relative to start location if true, absolute if false (default: absolute)
			--   easing: an easing function for the movement (default: linear)
			--   immediate: whether this move is queued or immediate (default: queued)
			--   anchors: an array of {x1,y1,x2,y2} with x1,y1 relative to start and x2,y2 relative to the end
			props=props or {}
			local move_data={
				x=x,
				y=y,
				relative=props.relative or false,
				easing=props.easing or linear,
				anchors=props.anchors or {}
			}
			if props.immediate then
				self:set_state("move",dur,move_data)
			else
				self:queue_state("move",dur,move_data)
			end
		end
	},
	player={
		hitbox_channel=2,
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
	magic_tile={
		hurtbox_channel=2,
		render_layer=3,
		draw=function(self)
			pal(7,rainbow[1+flr(scene_frame/4)%#rainbow])
			rectfill(self.x-4,self.y-3,self.x+4,self.y+3,1)
			rect(self.x-4,self.y-3,self.x+4,self.y+3,7)
			rect(self.x-2,self.y-1,self.x+2,self.y+1,7)
		end,
		on_death=function(self)
			freeze_frames=max(freeze_frames,1)
			screen_shake_frames=max(screen_shake_frames,2)
			spawn_entity("magic_tile_fade",{x=self.x,y=self.y})
			local i
			for i=1,20 do
				local angle=rnd_int(0,360)
				local speed=rnd_int(7,15)
				local cos_angle=cos(angle/360)
				local sin_angle=sin(angle/360)
				spawn_entity("rainbow_spark",{
					x=self.x+5*cos_angle,
					y=self.y+5*sin_angle,
					vx=speed*cos_angle,
					vy=speed*sin_angle-10,
					frames_to_death=rnd_int(13,19)
				})
			end
		end
	},
	magic_tile_fade={
		frames_to_death=6,
		render_layer=4,
		draw=function(self)
			rectfill(self.x-4,self.y-3,self.x+4,self.y+3,ternary(self.frames_alive>3,6,7))
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
			self.frames_alive=player.frames_alive
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
	playing_card={
		hitbox_channel=1,
		is_red=false,
		draw=function(self)
			palt(11,true)
			if self.is_red then
				pal(5,8)
				pal(6,15)
			end
			local f=flr(self.frames_alive/5)%4
			if self.vx<0 then
				f=(6-f)%4
			end
			sspr2(64+f*5,103,5,10,self.x-5,self.y-7)
			sspr2(64+f*5,103,5,10,self.x,self.y-7,true,true)
			-- pset(self.x,self.y,9)
		end
	},
	comet_mark={
		comet=nil,
		render_layer=3,
		update=function(self)
			if self.comet and not self.comet.is_alive then
				self:die()
			end
		end,
		draw=function(self)
			palt(11,true)
			pal(7,color_ramps[14][2+flr(self.frames_alive/4)%3])
			sspr(43,87,9,7,self.x-4,self.y-3)
		end,
		spawn_comet=function(self,x,y)
			self.comet=spawn_entity("comet",{color=rnd_from_list({7,14,15}),x=x,y=y,target_x=self.x,target_y=self.y,vx=rnd_int(-5,5),vy=rnd_int(-7,-1)})
		end
	},
	flash={
		color=14,
		frames_to_death=6,
		render_layer=10,
		draw=function(self)
			palt(11,true)
			pal2(7,color_ramps[self.color][3+flr(self.frames_alive/2)])
			sspr(5*flr(self.frames_alive/2),108,5,9,self.x-2,self.y-4)
			-- pset(self.x,self.y,8)
		end
	},
	magic_mirror={
		extends="movable",
		face=4,
		wearing_top_hat=true,
		update=function(self)
			self:apply_move()
			self:apply_velocity()
		end,
		move_to_player_col=function(self)
			self:queue_state("move_to_player_col",0)
		end,
		on_enter_state=function(self)
			if self.state=="move_to_player_col" then
				self:move(10*player:col()-5,-20,30,{easing=ease_out,immediate=true,anchors={0,10,0,-10}})
			else
				self:super_on_enter_state()
			end
		end,
		draw=function(self)
			palt(11,true)
			-- draw mirror
			pal(15,9)
			sspr2(121,58,7,30,self.x-6,self.y-12)
			pal(15,15)
			sspr2(121,58,7,30,self.x,self.y-12,true)
			pset(self.x-1,self.y+16,4)
			-- draw face
			if self.face==3 then
				palt(11,false)
				palt(9,true)
			end
			local flip_horizontal=(self.face==2 and self.frames_alive%8<4)
			local flip_vertical=(self.face==2 and (self.frames_alive+2)%8<4)
			sspr2(73+11*self.face,99,11,14,self.x-5,self.y-7,flip_horizontal,flip_vertical)
			if self.face==3 then
				palt(11,true)
				palt(9,false)
			end
			-- draw top hat
			if self.wearing_top_hat then
				pal(6,5)
				sspr2(121,49,7,9,self.x-6,self.y-15)
				pal(6,6)
				sspr2(121,49,7,9,self.x,self.y-15,true)
			end
		end
	},
	magic_mirror_hand={
		-- is_right_hand
		render_layer=7,
		extends="movable",
		pose=1,
		init=function(self)
			self.dir=ternary(self.is_right_hand,-1,1)
		end,
		move_to_row=function(self,row)
			-- lasts 20 frames
			self:queue_state("change_pose",0,3)
			self:move(ternary(self.is_right_hand,90,-10),8*row-4,20,{easing=ease_in_out,anchors={-self.dir*10,-10,-self.dir*10,10}})
			self:queue_state("change_pose",0,2)
		end,
		wait_for_card=function(self)
			self:pause(23)
		end,
		throw_card=function(self,row)
			-- 6 frames before throw, 20 frames after
			self:move_to_row(row)
			self:pause(6)
			self:queue_state("change_pose",0,1)
			self:queue_state("throw_card",0)
			self:pause(14)
			self:queue_state("change_pose",0,2)
			self:pause(6)
		end,
		throw_cards=function(self)
			if self.is_right_hand then
				self:throw_card(1)
				self:throw_card(3)
				self:throw_card(5)
			else
				self:wait_for_card()
				self:throw_card(2)
				self:throw_card(4)
			end
		end,
		on_enter_state=function(self)
			if self.state=="change_pose" then
				self.pose=self.state_data
			elseif self.state=="throw_card" then
				spawn_entity("playing_card",{x=self.x+10*self.dir,y=self.y,vx=self.dir,is_red=(rnd()<0.5)})
			end
			self:super_on_enter_state()
		end,
		update=function(self)
			self:apply_move()
			self:apply_velocity()
		end,
		draw=function(self)
			palt(11,true)
			local r=self.is_right_hand
			if self.pose==1 then
				sspr2(83,92,10,7,self.x-ternary(r,8,1),self.y-3,r)
			elseif self.pose==2 then
				sspr2(93,92,7,7,self.x-ternary(r,5,1),self.y-3,r)
			elseif self.pose==3 then
				sspr2(100,89,12,10,self.x-ternary(r,4,7),self.y-8,r)
			elseif self.pose==4 then
				sspr2(112,88,8,11,self.x-ternary(r,3,4),self.y-9,r)
			elseif self.pose==5 then
				sspr2(112+8,88,8,11,self.x-ternary(r,4,3),self.y-9,r)
			end
		end
	},
	rainbow_spark={
		render_layer=6,
		init=function(self)
			self.prev_x=self.x
			self.prev_y=self.y
		end,
		update=function(self)
			self.vx*=0.75
			self.vy*=0.75
			self.vy+=0.1
			self.prev_x=self.x
			self.prev_y=self.y
			self:apply_velocity()
		end,
		draw=function(self)
			line(self.prev_x,self.prev_y,self.x,self.y,rainbow[1+flr(scene_frame/4)%#rainbow])
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
		render_layer=9,
		color=14,
		frames_to_death=30,
		init=function(self)
			self.prev_x=self.x
			self.prev_y=self.y
		end,
		update=function(self)
			self.prev_x=self.x
			self.prev_y=self.y
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
		end,
		draw=function(self)
			line(self.x,self.y,self.prev_x,self.prev_y,self.color)
		end,
		on_death=function(self)
			spawn_entity("comet_explosion",{x=self.target_x,y=self.target_y})
		end
	},
	comet_explosion={
		hitbox_channel=1, -- player
		render_layer=4,
		frames_to_death=10,
		update=function(self)
			if self.frames_alive>=2 then
				self.hitbox_channel=0
			end
		end,
		draw=function(self)
			sspr(40+16*flr(self.frames_alive/2),48,16,16,self.x-7,self.y-8)
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
	-- rect(0,0,63,63,1)
	-- rect(66,0,127,63,1)
	-- rect(0,66,63,127,1)
	-- rect(66,66,127,127,1)
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
	player=spawn_entity("player",{x=10*3+5,y=8*2+4})
	spawn_entity("player_reflection",{x=10*4+5,y=8*2+4})
	local mirror=spawn_entity("magic_mirror",{x=40,y=-44})
	local left_hand=spawn_entity("magic_mirror_hand",{x=20,y=-44})
	local right_hand=spawn_entity("magic_mirror_hand",{x=60,y=-44,is_right_hand=true})

	mirror:pause(30)
	mirror:move_to_player_col()
	left_hand:throw_cards()
	right_hand:throw_cards()

	spawn_entity("magic_tile",{x=10*3-5,y=8*4-4})
	spawn_entity("magic_tile",{x=10*4-5,y=8*4-4})
	spawn_entity("magic_tile",{x=10*5-5,y=8*4-4})
	spawn_entity("magic_tile",{x=10*6-5,y=8*4-4})
	spawn_entity("magic_tile",{x=10*7-5,y=8*4-4})
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
	-- check for hits
	local i,j,entity,entity2
	for i=1,#entities do
		entity=entities[i]
		for j=1,#entities do
			entity2=entities[j]
			if i!=j and band(entity.hitbox_channel,entity2.hurtbox_channel)>0 and entity:is_hitting(entity2) and entity2.invincibility_frames<=0 and entity:on_hit(entity2)!=false then
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
	if entity1.render_layer==entity2.render_layer then
		return entity1:row()>entity2:row()
	else
		return entity1.render_layer>entity2.render_layer
	end
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
			is_hitting=function(self,entity)
				return self:row()==entity:row() and self:col()==entity:col()
			end,
			on_hit=noop,
			on_hurt=function(self)
				self:die()
			end,
			-- state methods
			set_state=function(self,state,dur,state_data)
				self.state_frames=0
				self.state=state
				self.state_end=dur or -1
				self.state_data=state_data or nil
				self:on_enter_state(self.state)
				self:check_for_state_change()
			end,
			queue_state=function(self,state,dur,state_data)
				add(self.future_state_data,state)
				add(self.future_state_data,dur or -1)
				add(self.future_state_data,state_data or false)
			end,
			queue_states=function(self,states)
				local i
				for i=1,#states,3 do
					self:queue_state(states[i],states[i+1],states[i+2])
				end
			end,
			pause=function(self,dur)
				self:queue_state("pause",dur)
			end,
			on_enter_state=noop,
			on_leave_state=noop,
			on_no_state=noop,
			check_for_state_change=function(self)
				if (self.state and self.state_end>=0 and self.state_frames>=self.state_end) or (not self.state and #self.future_state_data>0) then
					self:on_leave_state(self.state)
					self.state_frames=0
					self.state=nil
					self.state_end=-1
					self.state_data=nil
					if #self.future_state_data>0 then
						local f=self.future_state_data
						self:set_state(remove_first(f),remove_first(f),remove_first(f))
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


-- easing functions
function linear(percent)
	return percent
end

function ease_in(percent)
	return percent^2
end

function ease_out(percent)
	return 1-ease_in(1-percent)
end

function ease_in_out(percent)
	if percent<0.5 then
		return ease_in(2*percent)/2
	else
		return 0.5+ease_out(2*(percent-0.5))/2
	end
end

-- helper functions
function make_bezier(x0,y0,x1,y1,x2,y2,x3,y3)
	return function(t)
		return (1-t)^3*x0+3*(1-t)^2*t*x1+3*(1-t)*t^2*x2+t^3*x3,(1-t)^3*y0+3*(1-t)^2*t*y1+3*(1-t)*t^2*y2+t^3*y3
	end
end

function pal2(c1,c2)
	pal(c1,c2)
	palt(c1,c2==0)
end

function sspr2(x,y,width,height,x2,y2,flip_horizontal,flip_vertical)
	sspr(x,y,width,height,x2,y2,width,height,flip_horizontal,flip_vertical)
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
20000000002e000000000e200000000020000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bbb5555
20000000002e000000000e2000000000200000000000000000000000000000000000000000000000000000000000000f0000000000000002000000000b005655
20000000002e000000000e20000000002000000000000000000000000000000000000000000700070007000000fe000e000ef00000200000000020000b005655
20000000002e000000000e200000000020000000000000000000000000000000000000000000700700700000000000000000000000000000000000000b005655
20000000002e000000000e2000000000200000000000000000000000000007070700000000770f0f0f0770000fe000000000ef0002000000000002000b005555
20000000002e000000000e20000000002000000000000077700000000000707f707000000000f00000f00000000000000000000000000000000000000b005555
20000000002e000000000e2000000000200000000000077777000000000007fff70000000000000e000000000000000000000000000000000000000001008888
22222222222eeeeeeeeeee222222222220000000000007777700000000077fffff770000077f00eee00f77000e00000000000e00000000000000000005555555
000000000000000000000000000000000000000000000777770000000000007f700000000000000e00000000f0000000000000f020000000000000200b555555
00000000000000000000000000000000000000000000000000000000000007070700000000000f000f000000000000000000000000000000000000000bbbbbbf
0000000000000000000000000000000000000000000000000000000000000007000000000000700f00700000000000000000000000000000000000000b0000f0
0000000000000000000000000000000000000000000000000000000000000000000000000007000700070000000e0000000e000000000000000000000b0000f0
0000000000000000000000000000000000000000000000000000000000000000000000000000000700000000000f000e000f000000020000000200000b0090f4
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f0000000000000002000000000b094499
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b009977
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b097777
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bf77777
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bf77777
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f777777
bbbb777bbbbbbbb7bbbbbbbeee00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f777777
b077777b000000770000bbefff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009777777
b777777b000000df0000bef777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009777777
b777777b000007f00000bef777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009777777
7777777b000007720000bef777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009777777
7777777b00000dd22000bef77700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b977777
7777dd7b00777d7d2000bef77700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b977777
7771177b07d7d777d200b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b047777
7722177b77f00d77fd00b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000bf94977
7d2277777d077dd7fd00b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b944999
f77777177007f0dd0dd0b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b099494
bdff711f007df07707f0b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b000094
b0dd71db0077007f07dfb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b000099
b0d17dfb007d007d0077b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b000009
b0d17f7b00770077700770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b000009
b0d1717b00700007d000b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b000009
b001111bbbbbbbbb77bbb0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b0000f9
b001111bb99999bbbbb9bbbbbbbbbbbbbbbbbbb9bbb000000000000000000000000000000000000000000000000000000000000000000000000000000b0000f9
bbb1111b0711170bb0917000bb0000000bb0007f90b000000000000000000000000000000000000000000000000000000000000000000000000000000b000099
00dbbbbb0711170bb9117000b977000779b0007ff9b77bbbbb77000000000000000000000000000000000000000000000000000000000000000000000bbbbbb4
007000bb007f700b91117000b911707ff9b0007fff9707777707000000000000000000000000000000000000000000000000000000000000b77bbbbbbbbb7bbb
007000bb0007000bb777f777b911f7fff9b777f777bb7000007b000000000000000000000000000000000000000000000000bbbb77bbbbbbb777000bb007700b
00f7171b007f700bb0007fff9911707ff991117000bb7007007b000000000000000000000000000000000000000000000000b0007700000bb077000bb007700b
00b7777b07fff70bb0007ff9b977000779b9117000bb7000007b000000000000000000000000000000000000000000000000b7700770000bb077700bb007700b
00bffffb07fff70bb0007f90bb0000000bb0917000b7077777070000000000000000000000000000000bb77677777bb777bbb7770670000bb0077077b007700b
0000000bb99999bbbbbbb9bbbbbbbbbbbbbbb9bbbbb77bbbbb770000000000000000000000000000000d777777777d777777b06770670077b776677777777077
bbbbbbbbbbbbbbbbbbb7bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb0000000000000000000000000000000d77dd7600bd77dd777706676677777777677b77767777
b00000700000bb00000000000bb00000000000bb00000000000b0000000000000000000000000000000d777777777d77777777776666776b7767677b7676777b
b00000700000b700000000000bb000000000077b0000000000070000000000000000000000000000000d77dd77777d77dd77b0666666660bb676777b6667760b
b77000000000bb000000000777b000000000077b00000000000b0000000000000000000000000000000d67777700bd677776b0006666dd0bb06676db6677600b
b00770077700bb000000007777b00000000070bb07000000000b0000000000000000000000000000000bb6666bbbbbb66666bbbbbbdddbbbbbb66dbbbddddbbb
b00000077770bb00700000777bb07700070000bb00000000000b00000000000000000000000000000000bbbb777bbbbbbbb766bbbb9999cbb9999bbbb777bbbb
b00007777770bb07770070000bb07700000000bb00000000000b00000000000000000000000000000000b077777760bb067667670b90accbbee09b077777770b
b00077777000bb07770000000bb00000000000bb00000000000b00000000000000000000000000000000b777776677bb676776767b9aaccbbee89b777777777b
b00077777000bb00700007700bb00000007000bb00000000000b00000000000000000000000000000000b777667766bb776767676b9aaccbbee89bddd777dddb
b00007770070bb00000077700bb00000000770bb00000000007b000000000000bbbbbbbbbbbbbb6bbbbb77667766666676766766766aaccbbee8877777777777
b00000000007bb00000007700bb00000000770bb00000000000b000000000000b0007b000bb0077b067766776666677767677677676aaccbbee8877d77777d77
b00000007000bb000000000007b00000000000bb00000000000b000000000000b0077b6777b0777b075777666667777667666766776aaccbbee887d7d777d7d7
b00000007000bb00000000000bb00000000000bb00000000000b000000000000b0777b7777b7777b077766666777776676767676766aaccbbee8877d77777d77
bbbbbbbbbbbbbbbbbbbbb7bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb000000000000b7775b777567575b077566677777667767676767666aaccbbee8877777777777
bbbbbbb7bbbbbbb000000000000000000000000000000000000000000000000067775b7775b7775b07756777776677767676767766111ee11cc1177d77777d77
b000bb070bb000b0000000000000000000000000000000000000000000000000b7777b7577b0777b0777b777667777bb676767667b911ee11cc19b7ddddddd7b
b000bb070bb000b0000000000000000000000000000000000000000000000000b0775b6777b0077b0777b766777777bb766767776b9ddddddddd9b677777776b
b070bb070bb070b0000000000000000000000000000000000000000000000000b0077b000bb0007b0677b077777770bb076676670b90ddddddd09b066777660b
77777b777bb777b0000000000000000000000000000000000000000000000000bbbb6bbbbbbbbbbbbbbbbbbb777bbbbbbbb767bbbb9999ddd9999bbbb666bbbb
b070bb070bb070b0000000000000000000000000000000000000000000000000bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb777bbbbbbbbbbbbbb7bbbbbbbbbb
b000bb070bb000b0000000000000000000000000000000000000000000000000b00000000000000bb00077700000000bb00077700000000bb00000000700000b
b000bb070bb000b0000000000000000000000000000000000000000000000000b00000000000000bb00777700000000bb00700007700000bb000000000000007
bbbbbbb7bbbbbbb0000000000000000000000000000000000000000000000000b00000000000000bb00777007700000bb000000077000777b07000000000000b
0000000000000000000000000000000000000000000000000000000000000000b00007707770000bb00000007700777bb077000000000777b00000000000000b
0000000000000000000000000000000000000000000000000000000000000000b00007777777000bb077000000007777b07700000000700bb00000000000000b
0000000000000000000000000000000000000000000000000000000000000000b00077777777000bb077700000770777b00000000077000bb00000000007000b
0000000000000000000000000000000000000000000000000000000000000000b00077777777000bb07770077770000bb00070007777000bb00000000000000b
0000000000000000000000000000000000000000000000000000000000000000b00777777777700bb00000777777000bb00000007777000bb000000007000007
0000000000000000000000000000000000000000000000000000000000000000b00777777777700bb00000777777000bb000007007770077700000000000000b
0000000000000000000000000000000000000000000000000000000000000000b00777777077700bb07700077777077b7770000000000077b00000000000000b
0123000000000000000000000000000000000000000000000000000000000000b00077770000000b777770000000077b777000000000070bb00000000000000b
4567000000000000000000000000000000000000000000000000000000000000b00077700000000b777770077000077bb07070770000000bb00000000000000b
89ab000000000000000000000000000000000000000000000000000000000000b00000000000000bb77000077000000bb00000770000000bb00000000000000b
cdef000000000000000000000000000000000000000000000000000000000000bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

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


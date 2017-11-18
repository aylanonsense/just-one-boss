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
	{7,15,10,9,4,2,1,0},
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

-- global debug vars
local debug_logs={}

-- global entity vars
local player
local entities
local new_entities
local entity_classes={
	movable={
		apply_move=function(self)
			if self.movement then
				self.movement.frames+=1
				local prev_x,prev_y=self.x,self.y
				local next_x,next_y=self.movement.fn(self.movement.easing(self.movement.frames/self.movement.duration))
				self.vx,self.vy=next_x-prev_x,next_y-prev_y
				if self.movement.frames>=self.movement.duration then
					self.x=self.movement.final_x
					self.y=self.movement.final_y
					self.vx=0
					self.vy=0
					self.movement=nil
				end
			end
		end,
		move=function(self,x,y,dur,props)
			-- is_relative,easing,anchor_x1,anchor_y1,anchor_x2,anchor_y2
			-- x,y: where to move to
			-- dur: the number of frames the move should take
			-- props: an object of the following optional properties:
			--   relative: movement is relative to start location if true, absolute if false (default: absolute)
			--   easing: an easing function for the movement (default: linear)
			--   anchors: an array of {x1,y1,x2,y2} with x1,y1 relative to start and x2,y2 relative to the end
			props=props or {}
			local start_x,start_y=self.x,self.y
			local end_x,end_y=x,y
			if props.relative then
				end_x+=start_x
				end_y+=start_y
			end
			local dx,dy=end_x-start_x,end_y-start_y
			local anchors=props.anchors or {}
			local anchor_x1=anchors[1] or dx/4
			local anchor_y1=anchors[2] or dy/4
			local anchor_x2=anchors[3] or -dx/4
			local anchor_y2=anchors[4] or -dy/4
			self.movement={
				frames=0,
				duration=dur,
				final_x=end_x,
				final_y=end_y,
				easing=props.easing or linear,
				fn=make_bezier(
					start_x,start_y,
					start_x+anchor_x1,start_y+anchor_y1,
					end_x+anchor_x2,end_y+anchor_y2,
					end_x,end_y)
			}
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
			palt(3,true)
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
			palt(3,true)
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
			palt(3,true)
			local f=flr(self.frames_alive/2.5)%4
			if self.vx>0 then
				f=(4-f)%4
			end
			sspr(7+9*f,85,9,9,self.x-4,self.y-ternary(f==0,7,9))
			-- pset(self.x,self.y,8)
		end
	},
	playing_card={
		frames_to_death=110,
		hitbox_channel=1,
		is_red=false,
		draw=function(self)
			palt(3,true)
			if self.is_red then
				pal(5,8)
				pal(6,15)
			end
			local f=flr(self.frames_alive/5)%4
			if self.vx<0 then
				f=(6-f)%4
			end
			sspr2(73+f*5,97,5,10,self.x-5,self.y-7)
			sspr2(73+f*5,97,5,10,self.x,self.y-7,true,true)
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
			palt(3,true)
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
			palt(3,true)
			pal2(7,color_ramps[self.color][3+flr(self.frames_alive/2)])
			sspr(5*flr(self.frames_alive/2),108,5,9,self.x-2,self.y-4)
			-- pset(self.x,self.y,8)
		end
	},
	flower_patch={
		render_layer=4,
		update=function(self)
			if self.frames_alive>self.bloom_frames+3 then
				self.hitbox_channel=0
			elseif self.frames_alive==self.bloom_frames then
				self.hitbox_channel=1 -- player
				self.frames_to_death=35
				local i
				for i=1,2 do
					spawn_entity("flower_petal",{
						x=self.x,
						y=self.y-5,
						vx=i-2,
						vy=rnd_num(-10,-1),
						color=self.color,
						swing_offset=rnd_int(1,10),
						frames_to_death=rnd_int(40,60)
					})
				end
			end
		end,
		draw=function(self)
			if self.frames_alive>self.hidden_frames then
				palt(4,true)
				pal2(8,self.color)
				pal2(14,color_ramps[self.color][3])
				local f=0
				if self.bloom_frames-self.frames_alive<=0 then
					f=2
				elseif self.bloom_frames-self.frames_alive<=2 then
					f=1
				end
				sspr2(94+9*f,95,9,8,self.x-4,self.y-4,self.flipped)
				-- pset(self.x,self.y,8)
			end
		end
	},
	flower_petal={
		update=function(self)
			self.vy+=0.1
			self.vx*=0.7
			self.vy*=0.7
			self.vx+=sin((self.frames_alive+self.swing_offset)/20)/10
			self:apply_velocity()
		end,
		draw=function(self)
			pset(self.x,self.y,self.color)
		end
	},
	magic_mirror={
		extends="movable",
		expression=1,
		wearing_top_hat=true,
		charge_frames=0,
		laser_preview_frames=0,
		laser_frames=0,
		hover_frames=0,
		hitbox_channel=1, -- player
		hover_dir=nil,
		init=function(self)
			self.left_hand=spawn_entity("magic_mirror_hand",{x=self.x-18,y=self.y+5})
			self.right_hand=spawn_entity("magic_mirror_hand",{x=self.x+18,y=self.y+5,is_right_hand=true})
			-- self:conjure_flowers()
			-- self.left_hand:throw_cards()
			-- self.right_hand:throw_cards()
			self:shoot_lasers()
		end,
		is_hitting=function(self,entity)
			return self.laser_frames>0 and entity:col()==self:col()
		end,
		update=function(self)
			decrement_counter_prop(self,"laser_preview_frames")
			decrement_counter_prop(self,"laser_frames")
			if decrement_counter_prop(self,"hover_frames") then
				self.vx=0
				self.vy=0
			end
			self:check_schedule()
			self:apply_move()
			if self.hover_frames>0 then
				if self.x<=5 then
					self.hover_dir=1
				elseif self.x>=75 then
					self.hover_dir=-1
				end
				self.vx=2*self.hover_dir
				self.vy=0
			end
			self:apply_velocity()
			if self.charge_frames>0 then
				decrement_counter_prop(self,"charge_frames")
				local angle=rnd_int(1,360)
				spawn_entity("charge_particle",{
					x=self.x+20*cos(angle/360),
					y=self.y+20*sin(angle/360),
					target_x=self.x,
					target_y=self.y,
					color=7
				})
			end
		end,
		change_expression=function(self,expression)
			self.expression=expression
		end,
		shoot_lasers=function(self)
			local hover_frames=25
			local laser_frames=65
			self.left_hand:grab_mirror(self)
			self:schedule(20,"change_expression",5)
			self:schedule(26,"move_to_player_col")
			self:schedule(36,"shoot_laser")
			local f=36+laser_frames
			local i
			for i=1,3 do
				self:schedule(f,"hover",hover_frames)
				f+=hover_frames
				self:schedule(f,"shoot_laser")
				f+=laser_frames
			end
		end,
		hover=function(self,frames,dir)
			self.hover_frames=frames
			self.hover_dir=dir or self.hover_dir or 1
		end,
		shoot_laser=function(self)
			local charge_frames=14
			local preview_frames=12
			local laser_frames=25
			self:change_expression(4)
			self:charge_laser(charge_frames)
			self:schedule(charge_frames,"preview_laser",preview_frames+laser_frames+4)
			self:schedule(charge_frames+preview_frames,"fire_laser",laser_frames)
			self:schedule(charge_frames+preview_frames,"change_expression",0)
			self:schedule(charge_frames+preview_frames+laser_frames,"change_expression",4)
		end,
		charge_laser=function(self,frames)
			self.charge_frames=frames
		end,
		preview_laser=function(self,frames)
			self.laser_preview_frames=frames
		end,
		fire_laser=function(self,frames)
			self.laser_frames=frames
		end,
		conjure_flowers=function(self)
			local increment=3
			local time_to_bloom=70
			self.left_hand:change_pose(1)
			self.left_hand:move(self.x-15,self.y,20)
			self.right_hand:change_pose(1)
			self.right_hand:move(self.x+15,self.y,20)
			self:schedule(20,"change_expression",2)
			self:schedule(30,"spawn_flowers",increment,time_to_bloom)
			self:schedule(29+time_to_bloom,"change_expression",3)
			self.left_hand:schedule(29+time_to_bloom,"change_pose",4)
			self.right_hand:schedule(29+time_to_bloom,"change_pose",4)
		end,
		spawn_flowers=function(self,increment,time_to_bloom)
			local restricted_col=rnd_int(0,3)
			local restricted_row=rnd_int(0,4)
			local flowers={}
			local i=rnd_int(0,increment-1)
			while i<40 do
				local c=i%8
				local r=flr(i/8)
				if (c!=restricted_col and (7-c)!=restricted_col) or r!=restricted_row then
					add(flowers,{
						x=10*c+5,
						y=8*r+4,
						bloom_frames=time_to_bloom,
						flipped=(rnd()<0.5),
						color=rnd_from_list({8,12,9,14})
					})
				end
				i+=rnd_int(1,increment)
			end
			shuffle_list(flowers)
			for i=1,#flowers do
				flowers[i].hidden_frames=i
				spawn_entity("flower_patch",flowers[i])
			end
		end,
		move_to_player_col=function(self,a,b,c,d)
			-- 20 frames
			self:move(10*player:col()-5,-20,20,{easing=ease_in,immediate=true,anchors={0,10,0,-10}})
		end,
		draw=function(self)
			palt(3,true)
			-- draw mirror
			pal(15,9)
			sspr2(121,98,7,30,self.x-6,self.y-12)
			pal(15,15)
			sspr2(121,98,7,30,self.x,self.y-12,true)
			pset(self.x-1,self.y+16,4)
			-- draw face
			if self.expression>0 then
				local flip_vertical=(self.expression==5 and (self.frames_alive)%4<2)
				pal(9,6)
				pal(15,7)
				sspr2(74+6*self.expression,114,6,14,self.x-5,self.y-7,false,flip_vertical)
				pal(9,7)
				pal(15,6)
				if self.expression==6 then
					sspr2(80+6*self.expression,114,6,14,self.x+1,self.y-7,false,flip_vertical)
				else
					sspr2(74+6*self.expression,114,6,14,self.x,self.y-7,true,flip_vertical)
				end
			end
			-- draw top hat
			if self.wearing_top_hat then
				pal(6,5)
				sspr2(121,89,7,9,self.x-6,self.y-15)
				pal(6,6)
				sspr2(121,89,7,9,self.x,self.y-15,true)
			end
			-- draw laser
			if self.laser_preview_frames%2==1 then
				line(self.x,self.y+7,self.x,60,14)
			end
			if self.laser_frames>0 then
				rect(self.x-5,self.y+4,self.x+5,60,14)
				rect(self.x-4,self.y+4,self.x+4,60,15)
				rectfill(self.x-3,self.y+4,self.x+3,60,7)
				-- line(self.x-4,self.y,self.x-4,60,7)
				-- line(self.x,1,self.x,39,14)
			end
		end
	},
	magic_mirror_hand={
		-- is_right_hand
		render_layer=7,
		extends="movable",
		held_mirror=nil,
		held_mirror_dx=0,
		held_mirror_dy=0,
		pose=3,
		init=function(self)
			self.dir=ternary(self.is_right_hand,-1,1)
		end,
		change_pose=function(self,pose)
			self.pose=pose
		end,
		move_to_row=function(self,row)
			-- lasts 20 frames
			self:change_pose(3)
			self:move(ternary(self.is_right_hand,90,-10),8*row-4,20,{easing=ease_in_out,anchors={-self.dir*10,-10,-self.dir*10,10}})
			self:schedule(20,"change_pose",2)
		end,
		grab_mirror=function(self,mirror)
			-- lasts 20 frames
			local dx=-3*self.dir
			local dy=12
			self:change_pose(3)
			self:move_to_mirror_handle(mirror,dx,dy)
			self:schedule(20,"hold_mirror",mirror,dx,dy)
			self:schedule(20,"change_pose",2)
		end,
		move_to_mirror_handle=function(self,mirror,dx,dy)
			-- lasts 20 frames
			self:move(mirror.x+dx,mirror.y+dy,20,{easing=ease_out,anchors={-10*self.dir,10,-25*self.dir,0}})
		end,
		hold_mirror=function(self,mirror,dx,dy)
			self.held_mirror=mirror
			self.held_mirror_dx=dx
			self.held_mirror_dy=dy
		end,
		release_mirror=function(self,mirror)
			-- lasts 25 frames
			self.held_mirror=nil
			self:change_pose(3)
			self:move(-15*self.dir,-3,25,{easing=ease_in,relative=true})
		end,
		throw_card=function(self)
			-- lasts 14 frames
			self:change_pose(1)
			spawn_entity("playing_card",{x=self.x+10*self.dir,y=self.y,vx=self.dir,is_red=(rnd()<0.5)})
			self:schedule(14,"change_pose",2)
		end,
		throw_card_at_row=function(self,row)
			-- 26 frames before, 14 frames after (40 total)
			self:move_to_row(row)
			self:schedule(26,"change_pose",1)
			self:schedule(26,"throw_card")
		end,
		throw_cards=function(self)
			-- lasts 168 frames?
			local t=56
			if self.is_right_hand then
				self:throw_card_at_row(1)
				self:schedule(t,"throw_card_at_row",3)
				self:schedule(2*t,"throw_card_at_row",5)
			else
				self:schedule(0.5*t,"throw_card_at_row",2)
				self:schedule(1.5*t,"throw_card_at_row",4)
			end
		end,
		update=function(self)
			self:check_schedule()
			self:apply_move()
			self:apply_velocity()
			if self.held_mirror then
				self.x=self.held_mirror.x+self.held_mirror_dx
				self.y=self.held_mirror.y+self.held_mirror_dy
				self.vx=self.held_mirror.vx
				self.vy=self.held_mirror.vy
			end
		end,
		draw=function(self)
			palt(3,true)
			local r=self.is_right_hand
			if self.pose==1 then
				sspr2(76,107,10,7,self.x-ternary(r,8,1),self.y-3,r)
			elseif self.pose==2 then
				sspr2(86,107,7,7,self.x-ternary(r,5,1),self.y-3,r)
			elseif self.pose==3 then
				sspr2(93,104,12,10,self.x-ternary(r,5,6),self.y-7,r)
			elseif self.pose==4 then
				sspr2(105,103,8,11,self.x-ternary(r,3,4),self.y-9,r)
			elseif self.pose==5 then
				sspr2(113,103,8,11,self.x-ternary(r,4,3),self.y-9,r)
			end
			-- pset(self.x,self.y,8)
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
	charge_particle={
		-- target_x,target_y,color
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
			palt(3,true)
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
	-- mirror:conjure_flowers()

	-- spawn_entity("magic_tile",{x=10*3-5,y=8*4-4})
	-- spawn_entity("magic_tile",{x=10*4-5,y=8*4-4})
	-- spawn_entity("magic_tile",{x=10*5-5,y=8*4-4})
	-- spawn_entity("magic_tile",{x=10*6-5,y=8*4-4})
	-- spawn_entity("magic_tile",{x=10*7-5,y=8*4-4})
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
		-- update the entity's schedule
		local i
		for i=1,#entity.scheduled do
			entity.scheduled[i][1]-=1
		end
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
	palt(3,true)
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
	-- draw debug text
	if #debug_logs>0 then
		camera()
		local i
		for i=1,#debug_logs do
			print(debug_logs[i],10,10*i+120-10*#debug_logs,8)
		end
	end
end


-- entity functions
function spawn_entity(class_name,args,skip_init)
	local super_class_name=entity_classes[class_name].extends
	local k,v
	local entity
	if super_class_name then
		entity=spawn_entity(super_class_name,args,true)
		entity.class_name=class_name
	else
		-- create default entity
		entity={
			class_name=class_name,
			is_alive=true,
			frames_alive=0,
			frames_to_death=0,
			render_layer=5,
			update_priority=5,
			-- hit props
			hitbox_channel=0,
			hurtbox_channel=0,
			invincibility_frames=0,
			-- schedule props
			scheduled={},
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
				self:check_schedule()
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
			-- schedule methods
			schedule=function(self,time,fn,...)
				local args={...}
				add(self.scheduled,{time,fn,args})
			end,
			check_schedule=function(self)
				local i
				local num_deleted=0
				local list=self.scheduled
				local to_call={}
				for i=1,#list do
					local item=list[i]
					if item[1]<=0 then
						add(to_call,item[2])
						add(to_call,item[3] or {})
						list[i]=nil
						num_deleted+=1
					else
						list[i-num_deleted],list[i]=item,nil
					end
				end
				for i=1,#to_call,2 do
					local fn=to_call[i]
					local args=to_call[i+1]
					if type(fn)=="function" then
						fn(self,unpack(args))
					else
						self[fn](self,unpack(args))
					end
				end
			end,
			clear_schedule=function(self)
				self.scheduled={}
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
	return 1-ease_out(1-percent)
end

function ease_out(percent)
	return percent^2
end

function ease_in_out(percent)
	if percent<0.5 then
		return ease_out(2*percent)/2
	else
		return 0.5+ease_in(2*(percent-0.5))/2
	end
end

-- helper functions
function debug_log(log,print_instead)
	if print_instead then
		color(8)
		print(log)
	else
		add(debug_logs,log)
	end
end

function unpack(list,from,to)
	from=from or 1
	to=to or #list
	if from<=to then
		return list[from],unpack(list,from+1,to)
	end
end

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

function rnd_num(min_val,max_val)
	return min_val+rnd(max_val-min_val)
end

-- if n is below min, wrap to max. if n is above max, wrap to min
function wrap(min_val,n,max_val)
	return ternary(n<min_val,max_val,ternary(n>max_val,min_val,n))
end

-- increment a counter, wrapping to 20000 if it risks overflowing
function increment_counter(n)
	if n>32000 then
		return n-12000
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

function shuffle_list(list)
	local i
	for i=1,#list do
		local j=rnd_int(i,#list)
		list[i],list[j]=list[j],list[i]
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
3ccccc33cc33333333333333cccc333333ccccc33333933cc3333333333333330000000000000000000000000000000000000000000000000038838833388833
cccccccccccccccc0330000cccccc3000ccccccc30008dccccc3300000000003000000000000000000000000000000000000000000000000008888ee838888e3
cccc1c1cccc1111c1c3000ccc11c13000cccc1c130000cccccc33000c11cccc3000000000000000000000000000000000000000000000000008888ee838888e3
cdcc1c1cddd1111c1c30cddcc11c13000dccc1c13000dcc1c1cc30ccc11111cc0000000000000000000000000000000000000000000000000038888833888883
cccccccccccccccccc300cccccccc3000ccccccc300ddcc1c1cc3dccddcccccc0000000000000000000000000000000000000000000000000030888033088803
ddcccccddcdddd00033000ddccddc3000ddcccdc3000ddccccc3dddccccccdd30000000000000000000000000000000000000000000000000033383333338333
ddddddddddd0000003300ddddddd3300dddddddd30000ddcccd3dddddddd00030000000000000000000000000000000000000000000000000000000000000000
3d333d33d33333333333333333d33333333333d3333333d33398333333d333330000000000000000000000000000000000000000000000000000000000000000
3ccccc33333333c33333333ccccc333333ccccc33333ccccc3333333333333330000000000000000000000000000000000000000000000000000000000000000
ccccccc300000ccc0330000ccccc33000ccccccc390ccccccc093000000000030000000000000000000000000000000000000000000000000000000000000000
ccccccc300000ccc033000ccccccc3000ccccccc30dcccccccd330d0000000d30000000000000000000000000000000000000000000000000000000000000000
dcccccd300000ccc033000ccccccc3000dcccccd380cdddddc0830dcccccccd30000000000000000000000000000000000000000000000000000000000000000
ccccccc30000ccccc33000dcccccd3000ccccccc300ddddddd0330dcccccccd30000000000000000000000000000000000000000000000000000000000000000
cdddddc30000dcccd33000dcdddcd3000cdddddc300ddddddd0330cdddddddc30000000000000000000000000000000000000000000000000000000000000000
ddddddd30000dcccd33000ddddddd3000ddddddd3000ddddd00330ddddddddd30000000000000000000000000000000000000000000000000000000000000000
3d000d330000cdddc33000ddddddd30000000d0330000d000003300ddddddd030000000000000000000000000000000000000000000000000000000000000000
30000033000ddddddd3000000ddd3300000000033000000000033000000000030000000000000000000000000000000000000000000000000000000000000000
30000033000ddddddd30000000d03300000000033000000000033000000000030000000000000000000000000000000000000000000000000000000000000000
333333333333d333d333333333d33333333333333333333333333333333333330000000000000000000000000000000000000000000000000000000000000000
333333333333ccccc333333333333333333333333333333333333333333333333333333333300000000000000000000000000000000000000000000000000000
30000033000ccccccc3000000c003300000000033000000000033000000000030000c00000300000000000000000000000000000000000000000000000000000
30000033000cc1c1cc300000cc0c3300000000033000000000033000000000030000c0c000300000000000000000000000000000000000000000000000000000
3ccccc330000c1c1c330000ccccc330000ccccc330000000000330000ccc0003000ccccc00300000000000000000000000000000000000000000000000000000
ccccccc30000c1c1d33000cc1c1cc3000ccccccc3000ccccc0033000c1c1c003d0ccccccc0300000000000000000000000000000000000000000000000000000
cc1c1cc30000c1c1d33000cc1c1cd3000cc1c1cc390ccccccc083000c1c1c0030dcccc11c0d00000000000000000000000000000000000000000000000000000
dc1c1cd30000d1c1d33000cd1c1cd3000cc1c1cd30dcccccccd330ddc1c1cd030ccc1c11cd300000000000000000000000000000000000000000000000000000
ccccccc30000ddccc33000ddccccc3000cdccccc380ccccccc0930dcc1c1cdd3000ccccccc300000000000000000000000000000000000000000000000000000
dcccccd300000ddd033000dcccccc3000dcccccc300cc1c1cc0330ccc1c1ccd30dcccccc00300000000000000000000000000000000000000000000000000000
ddddddd300000ddd033000ddddddd3000ddddddd300cc1c1cc0330ccc1c1ccc300ddddddd0300000000000000000000000000000000000000000000000000000
3d333d33333333d33333333d3333333333d333333333ccccc3333333dddddd33333d333d33300000000000000000000000000000000000000000000000000000
51111111115000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11555555511000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
15511111551000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011111111111111
15111511151000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011000000000003
15115551151000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010110000111111
15111511151000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010110011110101
15511111551000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011001111101013
11555555511000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000031111111010101
51111111115000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030001110101013
51111111115000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030001101010101
11555555511000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030001010001003
15511111551000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030001100000003
15111511151000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000030001000000003
15115151151000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000033331333333333
15111511151000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
15511111551000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
11555555511000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
51111111115000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
33333333333333333333333333333333333377733333333333333733333333330000000000000000000000000000000000000000000000000000000000000000
30000000000000033000777000000003300077700000000330000000070000030000000000000000000000000000000000000000000000000000000000000000
30000000000000033007777000000003300700007700000330000000000000070000000000000000000000000000000000000000000000000000000000000000
30000000000000033007770077000003300000007700077730700000000000030000000000000000000000000000000000000000000000000000000000000000
30000770777000033000000077007773307700000000077730000000000000030000000000000000000000000000000000000000000000000000000000000000
30000777777700033077000000007777307700000000700330000000000000030000000000000000000000000000000000000000000000000000000000000000
30007777777700033077700000770777300000000077000330000000000700030000000000000000000000000000000000000000000000000000000000000000
30007777777700033077700777700003300070007777000330000000000000030000000000000000000000000000000000000000000000000000000000000000
30077777777770033000007777770003300000007777000330000000070000070000000000000000000000000000000000000000000000000000000000000000
30077777777770033000007777770003300000700777007770000000000000030000000000000000000000000000000000000000000000000000000000000000
30077777707770033077000777770773777000000000007730000000000000030000000000000000000000000000000000000000000000000000000000000000
30007777000000037777700000000773777000000000070330000000000000030000000000000000000000000000000000000000000000000000000000000000
30007770000000037777700770000773307070770000000330000000000000030000000000000000000000000000000000000000000000000000000000000000
30000000000000033770000770000003300000770000000330000000000000030000000000000000000000000000000000000000000000000000000000000000
33333333333333333333333333333333333333333333333333333333333333330000000000000000000000000000000000000000000000000000000000000000
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
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003335555
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003005655
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003005655
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003005655
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003005555
33333333333333333337333333333333333333333333333333330000000000000000000000000000000000000000000000000000000000000000000003005555
30000070000033000000000003300000000000330000000000030000000000000000000000000000000000000000004444444444444444444e84448441008888
3000007000003700000000000330000000000773000000000007000000000000000000000000000000000000000000880000088408000804e88008ee45555555
37700000000033000000000777300000000007730000000000030000000000000000000003333333333333363333308088888084880008848883088e83555555
30077007770033000000007777300000000070330700000000030000000000000000000003000730003300773067704800000844008380044b30b3884333333f
3000000777703300700000777330770007000033000000000003000000000000000000000300773677730777307570480080084400383004408e8300430000f0
300007777770330777007000033077000000003300000000000300000000000000000000030777377773777730777048000008440883000443eee0b0430000f0
3000777770003307770000000330000000000033000000000003000000000000000000000377753777567575307750808888808400800004408e8000430090f4
3000777770003300700007700330000000700033000000000003000000000000000000000677753777537775307750884444488444444444444b444443094499
30000777007033000000777003300000000770330000000000730000000000000000000003777737577307773077700000000000037733333333373333009977
30000000000733000000077003300000000770330000000000030000000000000000000003077536777300773077733337733333337770003300770033097777
30000000700033000000000007300000000000330000000000030000000000000000000003007730003300073067730007700000330770003300770033f77777
30000000700033000000000003300000000000330000000000030000000000000000000003333633333333333333337700770000330777003300770033f77777
3333333333333333333337333333333333333333333333333333000000000000000000000000337767777733777333777067000033007707730077003f777777
3333333733333330000000000000000000000000000000000000000000000000000000000000d777777777d7777773067706700773776677777777077f777777
3000330703300030000000000000000000000000000000000000000000000000000000000000d77dd76003d77dd7777066766777777776773777677779777777
3000330703300030000000000000000000000000000000000000000000000000000000000000d777777777d77777777776666776377676773767677739777777
3070330703307030000000000000000000000000000000000000000000000000000000000000d77dd77777d77dd7730666666660336767773666776039777777
7777737773377730000000000000000000000000000000000000000000000000000000000000d677777003d67777630006666dd03306676d3667760039777777
307033070330703000000000000000000000000000000000000000000000000000000000000033666633333366666333333ddd33333366d333dddd3333977777
300033070330003000000000000000000000000000000000000000000000000000000000000000003333773333663333773333773333f63333cbb33333977777
3000330703300030000000000000000000000000000000000000000000000000000000000000000030777730666630777730f77730979630accbbee033047777
333333373333333000000000000000000000000000000000000000000000000000000000000000003777773666663ddd77377ff737f9f73aaccbbee833f94977
000000000000000000000000000000000000000000000000000000000000000000000000000000003ddd773777773777773ff7963f76763aaccbbee833944999
0000000000000000000000000000000000000000000000000000000000000000000000000000000077777777dd7777d777ff66f7f7ff966aaccbbee883099494
0000000000000000000000000000000000000000000000000000000000000000000000000000000077d7777777d77d7d7799ff667679f76aaccbbee883000094
000000000000000000000000000000000000000000000000000000000000000000000000000000007d7d7777777777777777996697f6766aaccbbee883000099
0000000000000000000000000000000000000000000000000000000000000000000000000000000077d7777d7d7777dddd699997f977976aaccbbee883000009
0000000000000000000000000000000000000000000000000000000000000000000000000000000077777777d77777dddd966777f79f766aaccbbee883000009
0000000000000000000000000000000000000000000000000000000000000000000000000000000077d77777777777dddd977ff76f9767111ee11cc113000009
0123000000000000000000000000000000000000000000000000000000000000000000000000000037dddd377ddd377ddd37779639f696311ee11cc1330000f9
45670000000000000000000000000000000000000000000000000000000000000000000000000000367777377d773677773799773f9f763ddddddddd330000f9
89a300000000000000000000000000000000000000000000000000000000000000000000000000003066773077773066773077773076f730ddddddd033000099
cdef00000000000000000000000000000000000000000000000000000000000000000000000000003333663333663333663333773333763333ddd33333333334

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


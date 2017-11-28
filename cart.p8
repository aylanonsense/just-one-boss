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
	4: coin (stationary)

symbols:
	up:		”
	down:	ƒ
	left:	‹
	right:	‘
]]

-- useful noop function
function noop() end

-- global constants
local color_ramp_str="751000007d5100007e82100076b351007f94210076d510007776d51077776d1077e821007fa9421077fa9410776b3510776cd510776d510077fe8210777f9410"
local color_ramps={}
local rainbow_color

-- global config vars
local speed_mode=true

-- global scene vars
local scenes
local scene
local scene_frame
local freeze_frames=0
local screen_shake_frames=0

-- global promise vars
local promises={}

-- global entity vars
local player
local player_health
local boss
local boss_health
local entities
local new_entities
local entity_classes={
	instructions={
		x=40,
		y=-29,
		button_presses={},
		num_buttons_pressed=0,
		update=function(self)
			local i
			for i=0,3 do
				if btn(i) and not self.button_presses[i] then
					self.num_buttons_pressed+=1
					self.frames_to_death,self.button_presses[i]=240-45*self.num_buttons_pressed,true
				end
			end
		end,
		draw=function(self)
			local x,y,fade=self.x,self.y,0
			if self.frames_to_death>0 then
				fade=min(0,flr(self.frames_to_death/15)-3)
			end
			print("press",x-9,y-18,get_color(6,fade))
			print("to move",x-13,y+16)
			print("”",x-3,y-9,self:choose_color(2,fade)) -- up
			print("‹",x-13,y-1,self:choose_color(0,fade)) -- left
			print("‘",x+7,y-1,self:choose_color(1,fade)) -- right
			print("ƒ",x-3,y+7,self:choose_color(3,fade)) -- down
		end,
		choose_color=function(self,dir,fade)
			return get_color(ternary(self.button_presses[dir],6,13),fade)
		end,
		on_death=function(self)
			spawn_magic_tile(50)
		end
	},
	movable={
		apply_move=function(self)
			if self.movement then
				self.movement.frames+=1
				local next_x,next_y=self.movement.fn(self.movement.easing(self.movement.frames/self.movement.duration))
				self.vx,self.vy=next_x-self.x,next_y-self.y
				if self.movement.frames>=self.movement.duration then
					self.x,self.y=self.movement.final_x,self.movement.final_y
					self.vx,self.vy=0,0
					self.movement=nil
				end
			end
		end,
		move=function(self,x,y,dur,easing,anchors,is_relative)
			local start_x,start_y=self.x,self.y
			local end_x,end_y=x,y
			if is_relative then
				end_x+=start_x
				end_y+=start_y
			end
			local dx,dy=end_x-start_x,end_y-start_y
			anchors=anchors or {dx/4,dy/4,-dx/4,-dy/4}
			self.movement={
				frames=0,
				duration=dur,
				final_x=end_x,
				final_y=end_y,
				easing=easing or linear,
				fn=make_bezier(
					start_x,start_y,
					start_x+anchors[1],start_y+anchors[2],
					end_x+anchors[3],end_y+anchors[4],
					end_x,end_y)
			}
			return max(0,dur-1)
		end
	},
	player={
		hitbox_channel=2, -- pickup
		hurtbox_channel=1, -- player
		facing="right",
		step_frames=0,
		teeter_frames=0,
		bump_frames=0,
		stun_frames=0,
		primary_color=12,
		secondary_color=13,
		eye_color=0,
		update=function(self)
			decrement_counter_prop(self,"stun_frames")
			decrement_counter_prop(self,"teeter_frames")
			decrement_counter_prop(self,"bump_frames")
			-- try moving
			if btnp(0) then
				self:queue_step("left")
			elseif btnp(1) then
				self:queue_step("right")
			elseif btnp(2) then
				self:queue_step("up")
			elseif btnp(3) then
				self:queue_step("down")
			end
			-- apply moves that were delayed from teetering/stun
			if self.next_step_dir and not self.step_dir then
				self:step(self.next_step_dir)
			end
			-- actually move
			if self.stun_frames<=0 then
				self.vx=0
				self.vy=0
				self:apply_step()
				local prev_col,prev_row=self:col(),self:row()
				self:apply_velocity()
				local col,row=self:col(),self:row()
				if prev_col!=col or prev_row!=row then
					-- teeter off the edge of the earth if the player tries to move off the map
					if col!=mid(1,col,8) or row!=mid(1,row,5) then
						self:undo_step(prev_col,prev_row)
						self.teeter_frames=11
					end
					-- bump into an obstacle
					if is_tile_occupied(col,row) then
						self:undo_step(prev_col,prev_row)
						self.bump_frames=11
						freeze_and_shake_screen(0,5)
					end
				end
			end
		end,
		draw=function(self)
			local spritesheet_x,spritesheet_y,spritesheet_height,dx,dy,facing=0,0,8,7,6,self.facing
			local flipped=(facing=="left")
			-- up/down sprites are below the left/right sprites in the spritesheet
			if facing=="up" then
				spritesheet_y,spritesheet_height,dx=8,11,5
			elseif facing=="down" then
				spritesheet_y,spritesheet_height,dx,dy=19,11,5,9
			elseif facing=="left" then
				dx=3
			end
			-- moving between tiles
			if self.step_frames>0 then
				spritesheet_x=44-11*self.step_frames
			end
			-- teetering off the edge or bumping into a wall
			if self.teeter_frames>0 or self.bump_frames>0 then
				if self.bump_frames>0 then
					spritesheet_x=66
				else
					local c=ternary(self.teeter_frames%4<2,8,9)
					pal2(c,0)
					pal2(17-c,self.secondary_color)
					spritesheet_x=44
				end
				if facing=="up" then
					dy+=3
				elseif facing=="down" then
					dy-=2
				elseif facing=="left" then
					dx+=4
				elseif facing=="right" then
					dx-=4
				end
				if self.teeter_frames<3 and self.bump_frames<3 then
					spritesheet_x=55
				end
			end
			-- getting hurt
			if self.stun_frames>0 then
				spritesheet_x,spritesheet_y,spritesheet_height,dx,dy=77,0,10,5,8
				flipped=self.stun_frames%6>3
			end
			-- draw the sprite
			pal2(3)
			pal2(12,self.primary_color)
			pal2(13,self.secondary_color)
			pal(1,self.eye_color)
			if self.invincibility_frames%4<2 or self.stun_frames>0 then
				sspr2(spritesheet_x,spritesheet_y,11,spritesheet_height,self.x-dx,self.y-dy,flipped)
			end
		end,
		undo_step=function(self,col,row)
			self.x=10*col-5
			self.y=8*row-4
			self.step_dir=nil
			self.next_step_dir=nil
			self.step_frames=0
		end,
		queue_step=function(self,dir)
			if not self:step(dir) then
				self.next_step_dir=dir
			end
		end,
		step=function(self,dir)
			if not self.step_dir and self.teeter_frames<=0 and self.bump_frames<=0 and self.stun_frames<=0 then
				self.facing,self.step_dir,self.step_frames,self.next_step_dir=dir,dir,4 -- ,nil
				return true
			end
		end,
		apply_step=function(self)
			local dir,dist=self.step_dir,self.step_frames
			if dir then
				local dist_vertical=ternary(dist>2,dist-1,dist)
				if dir=="left" then
					self.vx-=dist
				elseif dir=="right" then
					self.vx+=dist
				elseif dir=="up" then
					self.vy-=dist_vertical
				elseif dir=="down" then
					self.vy+=dist_vertical
				end
				if decrement_counter_prop(self,"step_frames") then
					self.step_dir=nil
					if self.next_step_dir then
						self:step(self.next_step_dir)
						self:apply_step()
					end
				end
			end
		end,
		on_hurt=function(self)
			freeze_and_shake_screen(4,12)
			self.invincibility_frames=60
			self.stun_frames=19
			player_health:lose_heart()
		end
	},
	player_health={
		x=63,
		y=122,
		visible=false,
		hearts=3,
		anim=nil,
		anim_frames=0,
		is_user_interface=true,
		update=function(self)
			if decrement_counter_prop(self,"anim_frames") then
				self.anim=nil
			end
		end,
		draw=function(self)
			if self.visible then
				pal2(3)
				local i
				for i=1,4 do
					local sprite
					sspr(0,30,9,7,self.x+8*i-24,self.y-3)
					if self.anim=="gain" and i==self.hearts then
						sprite=mid(1,5-flr(self.anim_frames/2),3)
					elseif self.anim=="lose" and i==self.hearts+1 then
						sprite=6
					elseif i<=self.hearts then
						sprite=4
					else
						sprite=0
					end
					if sprite!=6 or self.anim_frames>=15 or (self.anim_frames+1)%4<2 then
						sspr(9*sprite,30,9,7,self.x+8*i-24,self.y-3)
					end
				end
			end
		end,
		gain_heart=function(self)
			if self.hearts<4 then
				self.hearts+=1
				self.anim,self.anim_frames="gain",10
			end
		end,
		lose_heart=function(self)
			if self.hearts>0 then
				self.hearts-=1
				self.anim,self.anim_frames="lose",20
			end
			if not self.visible then
				self.visible=true
				freeze_and_shake_screen(20,0)
			end
		end
	},
	boss_health={
		x=63,
		y=5,
		visible=false,
		health=0,
		visible_health=0,
		rainbow_frames=0,
		is_user_interface=true,
		update=function(self)
			if self.visible_health<self.health then
				self.visible_health+=1
			end
			if self.visible_health>self.health then
				self.visible_health-=1
			end
			decrement_counter_prop(self,"rainbow_frames")
		end,
		draw=function(self)
			if self.visible then
				local x,y=self.x,self.y
				if self.rainbow_frames>0 then
					pal2(5,16)
				end
				rect(x-30,y-3,x+30,y+3,5)
				rectfill(x-30,y-3,x+mid(-30,-31+self.visible_health,29),y+3,5)
			end
		end,
		gain_health=function(self,health)
			self.health=mid(0,self.health+health,60)
			self.rainbow_frames=15+(self.health-self.visible_health)
		end
	},
	magic_tile_spawn={
		frames_to_death=10,
		draw=function(self)
			if self.frames_to_death<=10 then
				local f=self.frames_to_death+3
				rect(self.x-f-1,self.y-f,self.x+f+1,self.y+f,ternary(self.frames_alive<4,5,6))
			end
		end,
		on_death=function(self)
			freeze_and_shake_screen(0,1)
			spawn_entity("magic_tile",self.x,self.y)
			spawn_particle_burst(self.x,self.y,4,16,4)
		end
	},
	magic_tile={
		render_layer=3,
		hurtbox_channel=2, -- pickup
		update=function(self)
			if is_tile_occupied(self:col(),self:row()) then
				self:die()
				spawn_magic_tile()
			end
		end,
		draw=function(self)
			local x,y,tile_color,bg_color,fade=self.x,self.y,16,1,max(0,3-flr(self.frames_alive/2))
			if self.frames_to_death>0 then
				tile_color,bg_color,fade=6,6,flr(self.frames_to_death/4)
			end
			-- draw background
			rectfill(x-4,y-3,x+4,y+3,get_color(bg_color,fade))
			-- draw tile
			rect(x-4,y-3,x+4,y+3,get_color(tile_color,fade))
			rect(x-2,y-1,x+2,y+1)
		end,
		on_hurt=function(self)
			freeze_and_shake_screen(2,4)
			self.hurtbox_channel,self.frames_to_death=0,6
			spawn_particle_burst(self.x,self.y,30,16,10)
			boss_health:gain_health(10)
			on_magic_tile_picked_up(self)
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
		on_hurt=function(self,entity)
			player:on_hurt(entity)
			self:copy_player()
		end,
		copy_player=function(self)
			local mirrored_directions={
				left="right",
				right="left",
				up="up",
				down="down"
			}
			self.x=80-player.x
			self.y=player.y
			self.facing=mirrored_directions[player.facing]
			self.step_frames=player.step_frames
			self.stun_frames=player.stun_frames
			self.teeter_frames=player.teeter_frames
			self.bump_frames=player.bump_frames
			self.invincibility_frames=player.invincibility_frames
			self.frames_alive=player.frames_alive
		end
	},
	playing_card={
		-- vx,is_red
		frames_to_death=110,
		hitbox_channel=1, -- player
		draw=function(self)
			pal2(3)
			-- some cards are red
			if self.is_red then
				pal2(5,8)
				pal2(6,15)
			end
			-- spin counter-clockwise when moving left
			local f=flr(self.frames_alive/5)%4
			if self.vx<0 then
				f=(6-f)%4
			end
			-- draw the card
			sspr2(10*f+75,104,10,10,self.x-5,self.y-7)
		end
	},
	flower_patch={
		render_layer=4,
		init=function(self)
			local c=rnd_int(1,3)
			self.color=({8,14,15})[c]
			self.accent_color=({15,7,14})[c]
			self.flipped=rnd()<0.5
		end,
		update=function(self)
			self.hitbox_channel=ternary(self.frames_to_death==35,1,0) -- player
		end,
		draw=function(self)
			pal2(4)
			pal2(8,self.color)
			pal2(15,self.accent_color)
			sspr2(9*ceil(self.frames_to_death/34)+88,85,9,8,self.x-4,self.y-4,self.flipped)
		end,
		bloom=function(self)
			self.frames_to_death=38
			local i
			for i=0,1 do
				spawn_entity("particle",self.x,self.y-2,{
					vx=(i-0.5),
					vy=rnd_num(-2,-1),
					friction=0.1,
					gravity=0.06,
					frames_to_death=rnd_int(10,17),
					color=self.color
				})
			end
		end
	},
	coin={
		extends="movable",
		init=function(self)
			self:promise("move",10*player:col()-3,8*player:row()-4,30,ease_out,{20,-30,10,-60})
				:and_then(2)
				:and_then(function()
					self.hitbox_channel=5 -- player, coin
					self.occupies_tile=true
					freeze_and_shake_screen(2,2)
				end)
				:and_then("move",-1,-4,3,ease_in,nil,true)
				:and_then(2)
				:and_then("move",-1,4,3,ease_out,nil,true)
				:and_then(function()
					self.hitbox_channel=1 -- player
					self.hurtbox_channel=4 -- coin
				end)
		end,
		update=function(self)
			self:apply_move()
			self:apply_velocity()
		end,
		draw=function(self)
			pal2(3)
			local sprite=0
			if self.frames_alive>20 then
				sprite=2
			end
			if self.frames_alive>=30 then
				sprite=4
			else
				sprite+=flr(self.frames_alive/3)%2
			end
			sspr(9*sprite,62,9,9,self.x-4,self.y-5)
		end,
		on_death=function(self)
			spawn_particle_burst(self.x,self.y,6,9,4)
		end
	},
	particle={
		extends="movable",
		friction=0,
		gravity=0,
		color=7,
		init=function(self)
			self.prev_x,self.prev_y=self.x,self.y
			self:apply_velocity()
		end,
		update=function(self)
			self.vy+=self.gravity
			self.vx*=(1-self.friction)
			self.vy*=(1-self.friction)
			self.prev_x,self.prev_y=self.x,self.y
			self:apply_move()
			self:apply_velocity()
		end,
		draw=function(self)
			local fade=0
			if self.fade_in_rate then
				fade=max(fade,3-flr(self.frames_alive/self.fade_in_rate))
			end
			if self.fade_out_rate then
				fade=min(fade,flr(self.frames_to_death/self.fade_out_rate)-3)
			end
			if self.reverse_fade then
				fade*=-1
			end
			line(self.x,self.y,self.prev_x,self.prev_y,get_color(self.color,fade))
		end
	},
	magic_mirror={
		extends="movable",
		x=40,
		y=-28,
		expression=4,
		laser_charge_frames=0,
		laser_preview_frames=0,
		hover_frames=0,
		hover_dir=1,
		visible=false,
		init=function(self)
			self.coins={}
			self.flowers={}
			self.left_hand=spawn_entity("magic_mirror_hand",self.x-18,self.y+5)
			self.right_hand=spawn_entity("magic_mirror_hand",self.x+18,self.y+5,{is_right_hand=true,dir=1})
		end,
		update=function(self)
			decrement_counter_prop(self,"laser_charge_frames")
			decrement_counter_prop(self,"laser_preview_frames")
			if decrement_counter_prop(self,"hover_frames") then
				self.vx=0
				self.vy=0
			end
			-- hover left and right
			if self.hover_frames>0 then
				if self.x<=5 then
					self.hover_dir=1
				elseif self.x>=75 then
					self.hover_dir=-1
				end
				self.vx,self.vy=2*self.hover_dir,0
			end
			self:apply_move()
			self:apply_velocity()
			-- create particles when charging laser
			if self.laser_charge_frames>0 then
				local x,y,angle=self.x,self.y,rnd()
				spawn_entity("particle",x+22*cos(angle),y+22*sin(angle),{
					color=14,
					fade_in_rate=3,
					fade_out_rate=2,
					reverse_fade=true,
					frames_to_death=18
				}):move(x,y,20,ease_out)
			end
		end,
		draw=function(self)
			local x,y=self.x,self.y
			pal2(3)
			if self.visible then
				-- draw mirror
				sspr2(115,84,13,30,self.x-6,self.y-12)
				-- draw face
				if self.expression>0 then
					sspr2(40+11*self.expression,114,11,14,x-5,y-7,false,self.expression==5 and (self.frames_alive)%4<2)
				end
			end
			if boss_health.rainbow_frames>0 then
				local i
				for i=1,15 do
					pal2(i,16)
				end
				pal2(3)
				sspr2(62,114,11,14,x-5,y-7,false,self.expression==5 and (self.frames_alive)%4<2)
				pal()
				pal2(3)
			end
			if self.visible then
				-- draw top hat
				if self.is_wearing_top_hat then
					sspr2(115,75,13,9,x-6,y-15)
				end
				-- draw laser preview
				if self.laser_preview_frames%2>0 then
					line(x,y+7,x,60,14)
				end
			end
		end,
		-- highest-level commands
		intro=function(self,speed_intro)
			if speed_intro then
				self:set_expression(1)
				self:don_top_hat()
				self.right_hand:appear()
				self.left_hand:appear()
				return self:promise(10)
			else
				return self:promise(20)
					:and_then(self.right_hand,"appear"):and_then(30)
					:and_then("set_pose",4):and_then(6)
					:and_then("set_pose",5):and_then(6)
					:and_then("set_pose",4):and_then(6)
					:and_then("set_pose",5):and_then(6)
					:and_then("set_pose",4):and_then(10)
					:and_then(self.left_hand,"appear"):and_then(30)
					:and_then("grab_mirror_handle",self):and_then(5)
					:and_then(self,"set_expression",5):and_then(33)
					:and_then("set_expression",6):and_then(25)
					:and_then("set_expression",5):and_then(20)
					:and_then("set_expression",1):and_then(30)
					:and_then(function()
						self.right_hand:tap_mirror(self)
					end):and_then(10)
					:and_then("don_top_hat"):and_then(10)
			end
		end,
		decide_next_action=function(self)
			-- local promise=self:shoot_lasers()
			-- local promise=self:conjure_flowers(3)
			-- local promise=self:throw_cards()
			local promise=self:throw_coins(3)
			return promise
				:and_then("return_to_ready_position"):and_then(60)
				:and_then(function()
					-- called this way so that the progressive decide_next_action
					--   calls don't result in an out of memory exception
					self:decide_next_action()
				end)
		end,
		-- medium-level commands
		conjure_flowers=function(self,density)
			-- generate a list of flower locations
			local flowers,i,safe_tile={},rnd_int(0,density),rnd_int(0,39)
			while i<40 do
				if i!=safe_tile and i!=safe_tile+7-safe_tile%8*2 then
					add(flowers,{i%8*10+5,8*flr(i/8)+4})
				end
				i+=rnd_int(1,density)
			end
			shuffle_list(flowers)
			-- concentrate
			local promise=self:promise(all_promises(
					{self.left_hand,"move_to_temple",self},
					{self.right_hand,"move_to_temple",self}
				)):and_then("set_expression",2)
			-- spawn the flowers
			self.flowers={}
			for i=1,#flowers do
				promise=promise:and_then("spawn_flower",flowers[i][1],flowers[i][2])
			end
			-- bloom the flowers
			return promise
				:and_then(30)
				:and_then("bloom_flowers")
				:and_then(30)
		end,
		throw_cards=function(self)
			return self:promise(all_promises(
					{self.left_hand,"throw_cards"},
					{self.right_hand,"throw_cards"}
				)):and_then(10)
		end,
		throw_coins=function(self,num_coins)
			local promise=self:promise(self.right_hand,"move_to_temple",self)
			local i
			for i=1,num_coins do
				promise=promise:and_then(self.right_hand,"set_pose",1)
					:and_then(self,"set_expression",7)
					:and_then(ternary(i==1,30,6))
					:and_then("set_expression",3)
					:and_then(self.right_hand,"set_pose",4)
					:and_then(self,"spawn_coin")
					:and_then(self,20)
			end
			return promise
		end,
		shoot_lasers=function(self)
			self.left_hand:disapper()
			return self:promise("set_held_state","right")
				:and_then("set_expression",5)
				:and_then("move",10*player:col()-5,-20,20,ease_in)
				:and_then("fire_laser")
				:and_then("hover",5)
				:and_then(10)
				:and_then("fire_laser")
				:and_then("hover",5)
				:and_then(10)
				:and_then("fire_laser")
		end,
		bloom_flowers=function(self)
			local i
			for i=1,#self.flowers do
				self.flowers[i]:bloom()
			end
			return self:promise("set_expression",3)
				:and_then(self.left_hand,"set_pose",5)
				:and_then(self.right_hand,"set_pose",5)
				:and_then(self)
		end,
		return_to_ready_position=function(self)
			return self:promise("set_expression",1)
				:and_then(self.left_hand,"set_pose",3)
				:and_then(self.right_hand,"set_pose",3)
				:and_then(self,"move_to_home")
				:and_then(function()
					if not self.left_hand.visible then
						self.left_hand:appear()
					end
					if not self.right_hand.visible then
						self.right_hand:appear()
					end
				end)
				:and_then("set_held_state",nil)
		end,
		move_to_home=function(self)
			local promise=self:promise()
			if self.x!=40 and self.y!=-28 then
				promise=promise:and_then("set_held_state","either")
			end
			return promise:and_then(function()
					local promises={}
					if self.x!=40 and self.y!=-28 then
						add(promises,{self,"move",40,-28,30,ease_in})
					end
					if not self.left_hand.held_mirror and self.left_hand.x!=22 and self.left_hand!=-23 then
						add(promises,{self.left_hand,"move",22,-23,30,ease_in,{-10,-10,-20,0}})
					end
					if not self.right_hand.held_mirror and self.right_hand.x!=58 and self.right_hand!=-23 then
						add(promises,{self.right_hand,"move",58,-23,30,ease_in,{10,-10,20,0}})
					end
					return all_promises(unpack(promises))()
				end)
		end,
		set_held_state=function(self,held_hand)
			local promises={}
			local lh,rh=self.left_hand,self.right_hand
			if held_hand=="either" then
				if rh.held_mirror then
					held_hand="right"
				else
					held_hand="left"
				end
			end
			if lh.held_mirror and held_hand!="left" then
				add(promises,{lh,"release_mirror"})
			elseif not lh.held_mirror and held_hand=="left" then
				add(promises,{lh,"grab_mirror_handle",self})
			end
			if rh.held_mirror and held_hand!="right" then
				add(promises,{rh,"release_mirror"})
			elseif not rh.held_mirror and held_hand=="right" then
				add(promises,{rh,"grab_mirror_handle",self})
			end
			if #promises>0 then
				return self:promise(all_promises(unpack(promises)))
			end
		end,
		fire_laser=function(self)
			return self:promise("charge_laser",14)
				:and_then(4)
				:and_then("preview_laser",10)
				:and_then("set_expression",0)
				:and_then("spawn_laser",20)
				:and_then("set_expression",5)
				:and_then("preview_laser",6)
				:and_then(20)
		end,
		charge_laser=function(self,frames)
			self.laser_charge_frames=frames
			return frames
		end,
		spawn_laser=function(self,frames)
			spawn_entity("mirror_laser",self.x,self.y,{frames_to_death=frames})
			return frames
		end,
		preview_laser=function(self,frames)
			self.laser_preview_frames=frames
			return frames
		end,
		hover=function(self,cols)
			self.hover_frames=5*cols+1
			return 5*cols
		end,
		despawn_coins=function(self)
			local i
			for i=1,#self.coins do
				self.coins[i]:die()
			end
			self.coins={}
			return 10
		end,
		-- lowest-level commands
		spawn_flower=function(self,x,y)
			add(self.flowers,spawn_entity("flower_patch",x,y))
			return 2
		end,
		spawn_coin=function(self)
			add(self.coins,spawn_entity("coin",self.x+12,self.y))
		end,
		don_top_hat=function(self)
			self.is_wearing_top_hat=true
			return self:poof(0,-10)
		end,
		poof=function(self,dx,dy)
			spawn_entity("poof",self.x+(dx or 0),self.y+(dy or 0))
			return 12
		end,
		set_expression=function(self,expression)
			self.expression=expression
		end,
	},
	magic_mirror_hand={
		-- is_right_hand,dir
		extends="movable",
		render_layer=7,
		pose=3,
		dir=-1,
		held_mirror=nil,
		update=function(self)
			self:apply_move()
			self:apply_velocity()
			if self.held_mirror then
				self.x=self.held_mirror[1].x+self.held_mirror[2]
				self.y=self.held_mirror[1].y+self.held_mirror[3]
			end
		end,
		draw=function(self)
			if self.visible then
				pal2(3)
				sspr2(12*self.pose-12,51,12,11,self.x-ternary(self.is_right_hand,7,4),self.y-8,self.is_right_hand)
			end
		end,
		-- highest-level commands
		throw_cards=function(self)
			local promise=self:promise(11-11*self.dir)
			local i
			for i=ternary(self.is_right_hand,1,2),5,2 do
				promise=promise:and_then("throw_card_at_row",i)
			end
			return promise
		end,
		grab_mirror_handle=function(self,mirror)
			return self:promise("set_pose",3)
				:and_then("move",mirror.x+2*self.dir,mirror.y+13,10,ease_out,{10*self.dir,5,0,20})
				:and_then("set_pose",2)
				:and_then(function()
					self.held_mirror={mirror,2*self.dir,13}
				end)
		end,
		tap_mirror=function(self,mirror)
			self:promise(9)
				:and_then("set_pose",5)
				:and_then(4)
				:and_then("set_pose",4)
			return self:promise("move",mirror.x+5*self.dir,mirror.y-3,10,ease_out,{0,-10,10*self.dir,-2})
				:and_then(2)
				:and_then("move",self.x,self.y,10,ease_in,{10*self.dir,-2,0,-10})
		end,
		-- medium-level commands
		throw_card_at_row=function(self,row)
			return self:promise("move_to_row",row):and_then(10)
				:and_then("set_pose",1):and_then("spawn_card"):and_then(10)
				:and_then("set_pose",2):and_then(4)
		end,
		release_mirror=function(self)
			self.held_mirror=nil
			return self:promise("set_pose",3)
				:and_then("move",15*self.dir,-7,25,ease_in,nil,true)
		end,
		appear=function(self)
			self.visible=true
			return self:poof()
		end,
		disapper=function(self)
			self.visible=false
			return self:poof()
		end,
		move_to_temple=function(self,mirror)
			return self:promise("set_pose",1)
				:and_then("move",mirror.x+13*self.dir,mirror.y,20)
		end,
		move_to_row=function(self,row)
			return self:promise("set_pose",3)
				:and_then("move",40+50*self.dir,8*row-4,20,ease_in_out,{10*self.dir,-10,10*self.dir,10})
				:and_then("set_pose",2)
		end,
		-- lowest-level commands
		set_pose=function(self,pose)
			if not self.held_mirror then
				self.pose=pose
			end
		end,
		poof=function(self,dx,dy)
			spawn_entity("poof",self.x+(dx or 0),self.y+(dy or 0))
			return 12
		end,
		spawn_card=function(self)
			spawn_entity("playing_card",self.x-10*self.dir,self.y,{vx=-self.dir,is_red=(rnd()<0.5)})
		end,
		--
		-- move_to_home=function(self,x,y)
		-- 	-- self:move(x-self.dir*18,y+5,30,{relative=false,easing=ease_in})
		-- end,
		-- move_to_mirror_handle=function(self,mirror,dx,dy)
		-- 	-- lasts 10 frames
		-- 	-- self:move(mirror.x+dx,mirror.y+dy,10,{easing=ease_out,anchors={-10*self.dir,5,0,20}})
		-- end,
	},
	mirror_laser={
		hitbox_channel=1, -- player
		draw=function(self)
			local x,y=self.x,self.y+4
			rectfill(x-5,y,x+5,100,14)
			rectfill(x-4,y,x+4,100,15)
			rectfill(x-3,y,x+3,100,7)
		end,
		is_hitting=function(self,entity)
			return self:col()==entity:col()
		end,
	},
	heart={
		frames_to_death=150,
		hurtbox_channel=2, -- pickup
		draw=function(self)
			pal2(3)
			local f=self.frames_to_death
			if f>30 or f%4>1 then
				if (f+4)%30>14 then
					pal2(14,8)
				end
				sspr2(ternary(f%30<20,36,45),30,9,7,self.x-4,self.y-5)
			end
		end,
		on_hurt=function(self)
			freeze_frames=2
			player_health:gain_heart()
			spawn_particle_burst(self.x,self.y,6,8,4)
			self:die()
		end
	},
	poof={
		frames_to_death=12,
		render_layer=9,
		draw=function(self)
			pal2(3)
			sspr2(16*flr(self.frames_alive/3),37,16,14,self.x-8,self.y-8)
		end
	}
}


-- primary pico-8 functions (_init, _update, _draw)
function _init()
	-- unpack the color ramps from hex to actual ints
	local i,j
	for i=0,15 do
		color_ramps[i]={}
		for j=1,8 do
			add(color_ramps[i],("0x"..(sub(color_ramp_str,8*i+j,8*i+j)))+0)
		end
	end
	-- set up the scenes now that the functions are defined
	scenes={
		game={init_game,update_game,draw_game}
	}
	-- run the "game" scene
	scene,scene_frame=scenes.game,0
	scene[1]()
end

local skip_frames=0
function _update()
	skip_frames=increment_counter(skip_frames)
	if skip_frames%1>0 then return end
	-- call the update function of the current scene
	if freeze_frames>0 then
		freeze_frames=decrement_counter(freeze_frames)
	else
		screen_shake_frames=decrement_counter(screen_shake_frames)
		scene_frame=increment_counter(scene_frame)
		-- update promises
		local num_promises,i=#promises
		for i=1,num_promises do
			promises[i]:update()
		end
		filter_list(promises,function(promise)
			return not promise.finished
		end)
		-- update the scene
		scene[2]()
	end
end

function _draw()
	-- clear the screen
	cls()
	-- call the draw function of the current scene
	scene[3]()
	-- draw debug info
	-- camera()
	-- print("mem:      "..flr(100*(stat(0)/1024)).."%",2,109,ternary(stat(1)>=1024,8,2))
	-- print("cpu:      "..flr(100*stat(1)).."%",2,116,ternary(stat(1)>=1,8,2))
	-- print("entities: "..#entities,2,123,ternary(#entities>50,8,2))
end


-- game functions
function init_game()
	calc_rainbow_color()
	-- reset everything
	entities,new_entities={},{}
	-- create starting entities
	player=spawn_entity("player",35,20)
	player_health=spawn_entity("player_health")
	boss=spawn_entity("magic_mirror")
	boss_health=spawn_entity("boss_health")
	if speed_mode then
		boss.visible=true
		player_health.visible=true
		boss_health.visible=true
		boss:intro(true):and_then("decide_next_action")
		spawn_magic_tile()
	else
		-- start the slow intro to the game
		spawn_entity("instructions")
	end
	-- if self.phase==0 then
	-- 	if self.health>=20 and not self.visible then
	-- 		self.visible=true
	-- 	end
	-- 	if self.health>=40 then
	-- 		boss.rainbow_frames=self.rainbow_frames
	-- 	end
	-- 	if self.health>=50 and not boss.visible then
	-- 		boss.visible=true
	-- 	end
	-- 	if self.health>=60 then
	-- 		-- boss:schedule(55,"intro")
	-- 	end
	-- end
	-- immediately add new entities to the game
	add_new_entities()
end

function update_game()
	calc_rainbow_color()
	-- sort entities for updating
	sort_list(entities,updates_before)
	-- update entities
	local entity
	for entity in all(entities) do
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
	local i
	for i=1,#entities do
		local entity,j=entities[i]
		for j=1,#entities do
			local entity2=entities[j]
			if i!=j and band(entity.hitbox_channel,entity2.hurtbox_channel)>0 and entity:is_hitting(entity2) then
				entity:on_hit(entity2)
				if entity2.invincibility_frames<=0 then
					entity2:on_hurt(entity)
				end
			end
		end
	end
	-- add new entities to the game
	add_new_entities()
	-- remove dead entities from the game
	filter_list(entities,function(entity)
		return entity.is_alive
	end)
	-- sort entities for rendering
	sort_list(entities,renders_on_top_of)
end

function draw_game()
	camera()
	-- shake the camera
	local shake_x=0
	if freeze_frames<=0 and screen_shake_frames>0 then
		shake_x=ceil(screen_shake_frames/3)*(scene_frame%2*2-1)
	end
	-- draw the background
	camera(shake_x,-11)
	draw_background()
	-- draw tiles
	camera(shake_x-23,-65)
	draw_tiles()
	-- draw entities
	foreach(entities,function(entity)
		if not entity.is_user_interface then
			entity:draw()
			pal()
		end
	end)
	-- draw ui
	camera(shake_x)
	draw_ui()
	-- draw guidelines
	-- camera()
	-- color(3)
	-- rect(0,0,126,127) -- bounding box
	-- rect(0,11,126,116) -- main area
	-- rect(6,2,120,8) -- top ui
	-- rect(33,2,93,8) -- top middle ui
	-- rect(22,11,104,116) -- main middle
	-- rect(22,64,104,106) -- play area
	-- rect(6,119,120,125) -- bottom ui
	-- rect(47,119,79,125) -- bottom middle ui
	-- line(63,0,63,127) -- mid line
	-- line(127,0,127,127) -- unused right line
end

function draw_background()
	-- draw "curtains"
	local curtains={1,83,7,57,18,25,22,9}
	local i
	for i=1,#curtains,2 do
		local x,y=curtains[i],curtains[i+1]
		line(x,0,x,y,2)
		line(126-x,0,126-x,y)
	end
	-- draw stars
	local stars={29,19,88,7,18,41,44,3,102,43,24,45,112,62,11,70,5,108,120,91,110,119}
	circ(18,41,1,1)
	circ(112,62,1)
	for i=1,#stars,2 do
		pset(stars[i],stars[i+1])
	end
end

function draw_tiles()
	pal2(3)
	-- draw tiles
	local c,r
	for c=0,7 do
		for r=0,4 do
			sspr2(93+(c+r)%2*11,76,11,9,10*c,8*r)
		end
	end
	-- draw some other grid stuff
	color(1)
	line(16,-1,64,-1)
	line(16,41,64,41)
	line(16,49,64,49)
	sspr2(68,90,20,5,30,46)
	for c=0,1 do
		sspr2(59,102,16,2,65*c,-1,c==1,true)
		sspr2(59,102,16,12,65*c,40,c==1)
	end
	pal()
end

function draw_ui()
	pal2(3)
	-- draw black boxes
	rectfill(0,0,127,10,0)
	rectfill(0,118,127,128)
	if false then
		-- draw score multiplier
		sspr2(117,0,11,7,6,2)
		print("4",8,3,0)
		-- draw score
		print("25700",101,3,1)
		-- draw lives
		sspr2(118,7,10,5,7,120)
		print("3",19,120)
		-- draw timer
		print("17:03",101,120)
	end
	-- draw ui entities
	pal()
	foreach(entities,function(entity)
		if entity.is_user_interface then
			entity:draw()
			pal()
		end
	end)
end


-- entity functions
function spawn_entity(class_name,x,y,args,skip_init)
	local k,v,entity
	local super_class_name=entity_classes[class_name].extends
	if super_class_name then
		entity=spawn_entity(super_class_name,x,y,args,true)
	else
		-- create default entity
		entity={
			-- lifetime props
			is_alive=true,
			frames_alive=0,
			frames_to_death=0,
			-- ordering props
			render_layer=5,
			update_priority=5,
			-- hit props
			hitbox_channel=0,
			hurtbox_channel=0,
			invincibility_frames=0,
			-- spatial props
			x=x or 0,
			y=y or 0,
			vx=0,
			vy=0,
			-- entity methods
			add_to_game=noop,
			init=noop,
			update=function(self)
				self:apply_velocity()
			end,
			apply_velocity=function(self)
				self.x+=self.vx
				self.y+=self.vy
			end,
			draw=noop,
			die=function(self)
				self:on_death()
				self.is_alive=false
			end,
			on_death=noop,
			col=function(self)
				return 1+flr(self.x/10)
			end,
			row=function(self)
				return 1+flr(self.y/8)
			end,
			-- hit methods
			is_hitting=function(self,entity)
				return self:row()==entity:row() and self:col()==entity:col()
			end,
			on_hit=noop,
			on_hurt=function(self)
				self:die()
			end,
			-- promise methods
			promise=function(self,ctx,...)
				local p
				if type(ctx)=="table" then
					p=make_promise(ctx,...)
				else
					p=make_promise(self,ctx,...)
				end
				p:start()
				return p
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
		entity:init(args)
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

function updates_before(a,b)
	return a.update_priority>b.update_priority
end

function renders_on_top_of(a,b)
	if a.render_layer==b.render_layer then
		return a:row()>b:row()
	end
	return a.render_layer>b.render_layer
end


-- tile functions
function tile_exists(col,row)
	return mid(1,col,8)==col and mid(1,row,5)==row
end

-- promise functions
function make_promise(ctx,fn,...)
	local args={...}
	return {
		ctx=ctx,
		and_thens={},
		start=function(self)
			if not self.started then
				self.started=true
				-- call callback (if there is one) and get the frames left
				local f=fn
				if type(fn)=="function" then
					f=fn(unpack(args))
				elseif type(fn)=="string" then
					f=self.ctx[fn](self.ctx,unpack(args))
				end
				-- the result of the fn call was a promise, when it's done, finish this promise
				if type(f)=="table" then
					if not f.ctx then
						f.ctx=self.ctx
					end
					f:and_then(self,"finish")
				-- wait a certain number of frames
				elseif f and f>0 then
					self.frames_to_finish=f
					add(promises,self)
				-- or just finish immediately if there's no need to wait
				else
					self:finish()
				end
			end
		end,
		finish=function(self)
			if not self.finished then
				self.finished=true
				foreach(self.and_thens,function(promise)
					promise:start()
				end)
			end
		end,
		update=function(self)
			if self.frames_to_finish and decrement_counter_prop(self,"frames_to_finish") then
				self:finish()
			end
		end,
		and_then=function(self,ctx,...)
			local promise
			if type(ctx)=="table" then
				promise=make_promise(ctx,...)
			else
				promise=make_promise(self.ctx,ctx,...)
			end
			-- start the promise now, or shcedule it to start when this promise finishes
			if self.finished then
				promise:start()
			else
				add(self.and_thens,promise)
			end
			return promise
		end
	}
end

function all_promises(...)
	local promises={...}
	return function()
		local promise,num_finished=make_promise(),0
		local i
		for i=1,#promises do
			local promise2=make_promise(unpack(promises[i]))
			promise2:start()
			promise2:and_then(function()
				num_finished+=1
				if num_finished==#promises then
					promise:finish()
				end
			end)
		end
		if #promises<=0 then
			promise:finish()
		end
		return promise
	end
end

-- magic tile functions
function on_magic_tile_picked_up(tile)
	spawn_magic_tile(100-min(tile.frames_alive,30)) -- 30 frame grace period
end

function spawn_magic_tile(frames_to_death)
	spawn_entity("magic_tile_spawn",10*rnd_int(1,8)-5,8*rnd_int(1,5)-4,{frames_to_death=max(10,frames_to_death)})
end

function spawn_particle_burst(x,y,num_particles,color,speed)
	local i
	for i=1,num_particles do
		local angle=(i+rnd(0.7))/num_particles
		local particle_speed=speed*rnd_num(0.5,1.2)
		spawn_entity("particle",x,y,{
			vx=particle_speed*cos(angle),
			vy=particle_speed*sin(angle)-speed/2,
			color=color,
			gravity=0.1,
			friction=0.25,
			frames_to_death=rnd_int(13,19)
		})
	end
end

-- drawing functions
function calc_rainbow_color()
	rainbow_color=8+flr(scene_frame/4)%6
	if rainbow_color==13 then
		rainbow_color=14
	end
	color_ramps[16]=color_ramps[rainbow_color]
end

function get_color(c,fade) -- fade between 3 (lightest) and -3 (darkest)
	return color_ramps[c or 0][4-fade]
end

function pal2(c1,c2,fade)
	local c3=get_color(c2,fade or 0)
	pal(c1,c3)
	palt(c1,c3==0)
end

function sspr2(x,y,width,height,x2,y2,flip_horizontal,flip_vertical)
	sspr(x,y,width,height,x2+0.5,y2+0.5,width,height,flip_horizontal,flip_vertical)
	-- rect(x2,y2,x2+width-1,y2+height-1,8)
end

-- tile functions
function is_tile_occupied(col,row)
	local i
	for i=1,#entities do
		local entity=entities[i]
		if entity.occupies_tile and entity:col()==col and entity:row()==row then
			return true
		end
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
	return ternary(percent<0.5,ease_out(2*percent)/2,0.5+ease_in(2*percent-1)/2)
end

-- helper functions
function freeze_and_shake_screen(freeze,shake)
	freeze_frames=max(freeze,freeze_frames)
	screen_shake_frames=max(shake,screen_shake_frames)
end

-- creates a bezier function from 4 sets of coordinates
function make_bezier(...) -- x1,y1,x2,...,y4
	local args={...}
	return function(t)
		local x,y=0,0
		local i
		for i=0,3 do
			local m=ternary(i%3>0,3,1)*t^i*(1-t)^(3-i)
			x+=m*args[2*i+1]
			y+=m*args[2*i+2]
		end
		return x,y
	end
end

-- round a number up to the nearest integer
function ceil(n)
	return -flr(-n)
end

-- if condition is true return the second argument, otherwise the third
function ternary(condition,if_true,if_false)
	return condition and if_true or if_false
end

-- unpacks an array so it can be passed as function arguments
function unpack(list,from,to)
	from,to=from or 1,to or #list
	if from<=to then
		return list[from],unpack(list,from+1,to)
	end
end

-- generates a random integer between min_val and max_val, inclusive
function rnd_int(min_val,max_val)
	return flr(min_val+rnd(1+max_val-min_val))
end

-- generates a random number between min_val and max_val
function rnd_num(min_val,max_val)
	return min_val+rnd(max_val-min_val)
end

function rnd_item(...)
	local args={...}
	return args[rnd_int(1,#args)]
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

-- shuffles a list randomly
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


__gfx__
33333ccccc33cc33333333333333cccc333333ccccc3333933cc33333333333333333333ccc333333c3333330000000000000000000000000000031111111113
3000cccccccccccccccc0330000cccccc3000ccccccc3008dccccc330000000003300000ccc033000c0c00030000000000000000000000000000011111111111
3000cccc1c1cccc1111c1c3000ccc11c13000cccc1c13000cccccc3300c11cccc330000cc1c03300ccccc0030000000000000000000000000000011111101011
3000cdcc1c1cddd1111c1c30cddcc11c13000dccc1c1300dcc1c1cc3ccc11111cc300ddcc1c03d0ccccccc030000000000000000000000000000011111110111
3000cccccccccccccccccc300cccccccc3000ccccccc30ddcc1c1cc3ccddcccccc30000cccc033dcccc11c0d0000000000000000000000000000011111101011
3000ddcccccddcdddd00033000ddccddc3000ddcccdc300ddccccc3ddccccccdd330000dccc033ccc1c11cd30000000000000000000000000000011111111111
3000ddddddddddd0000003300ddddddd3300dddddddd3000ddcccd3ddddddd000330000dddd03300ccccccc30000000000000000000000000000031111111113
33333d333d33d33333333333333333d33333333333d333333d3339833333d333333333d333d333dcccccc003000000000000000000000000000000ddddd33333
333ccccc33333333c33333333ccccc333333ccccc333333ccccc333333333333333333333333330ddddddd03000000000000000000000000000001d0d0d00101
30ccccccc033000ccc0003300ccccc00330ccccccc0390ccccccc093000000000330000000003333d333d333000000000000000000000000000003d0d0d00013
30ccccccc033000ccc000330ccccccc0330ccccccc033dcccccccd33d0000000d33d0000000d3000000000000000000000000000000000000000015ddd500101
30dcccccd033000ccc000330ccccccc0330dcccccd0380cdddddc083dcccccccd33cdcccccdc300000000000000000000000000000000000000000ddddd33333
30ccccccc03300ccccc00330dcccccd0330ccccccc0330ddddddd033dcccccccd33ccccccccc3000000000000000000000000000000000000000000000000000
30cdddddc03300dcccd00330dcdddcd0330cdddddc0330ddddddd033cdddddddc33ddddddddd3000000000000000000000000000000000000000000000000000
30ddddddd03300dcccd00330ddddddd0330ddddddd03300ddddd0033ddddddddd3300ddddd003000000000000000000000000000000000000000000000000000
300d000d003300cdddc00330ddddddd03300000d00033000d00000330ddddddd03300d000d003000000000000000000000000000000000000000000000000000
3000000000330ddddddd0330000ddd00330000000003300000000033000000000330000000003000000000000000000000000000000000000000000000000000
3000000000330ddddddd03300000d000330000000003300000000033000000000330000000003000000000000000000000000000000000000000000000000000
33333333333333d333d333333333d333333333333333333333333333333333333333333333333000000000000000000000000000000000000000000000000000
33333333333333ccccc3333333333333333333333333333333333333333333333333333333333000000000000000000000000000000000000000000000000000
3000000000330ccccccc0330000c0000330000000003300000000033000000000330000000003000000000000000000000000000000000000000000000000000
3000000000330cc1c1cc033000cc0c00330000000003300000000033000000000330000000003000000000000000000000000000000000000000000000000000
300ccccc003300c1c1c003300ccccc003300ccccc003300000000033000ccc000330000000003000000000000000000000000000000000000000000000000000
30ccccccc03300c1c1d00330cc1c1cc0330ccccccc03300ccccc003300c1c1c00330000000003000000000000000000000000000000000000000000000000000
30cc1c1cc03300c1c1d00330cc1c1cd0330cc1c1cc0390ccccccc09300c1c1c00330000000003000000000000000000000000000000000000000000000000000
30dc1c1cd03300d1c1d00330cd1c1cd0330cc1c1cd033dcccccccd33ddc1c1cd03d00ccccc00d000000000000000000000000000000000000000000000000000
30ccccccc03300ddccc00330ddccccc0330cdccccc0380ccccccc083dcc1c1cdd33dcccccccd3000000000000000000000000000000000000000000000000000
30dcccccd033000ddd000330dcccccc0330dcccccc0330cc1c1cc033ccc1c1ccd33ccccccccc3000000000000000000000000000000000000000000000000000
30ddddddd033000ddd000330ddddddd0330ddddddd0330cc1c1cc033ccc1c1ccc33cc11c11cc3000000000000000000000000000000000000000000000000000
333d333d33333333d33333333d3333333333d3333333333ccccc333333dddddd3333333333333000000000000000000000000000000000000000000000000000
33333333333333333383333333883333333833333333333333333338833333000000000000000000000000000000000000000000000000000000000000000000
30550550330550550338880888330880880330880880330088800388880588300000000000000000000000000000000000000000000000000000000000000000
35005005335005005338888ee8338888ee8338888ee83308888e03888050ee800000000000000000000000000000000000000000000000000000000000000000
35000005335888885338888ee8338888ee8338888ee83308888e03388808ee800000000000000000000000000000000000000000000000000000000000000000
30500050330588850330888880330888880330888880330888880330800088300000000000000000000000000000000000000000000000000000000000000000
30050500330058500330888880330088800330088800330088800330050880300000000000000000000000000000000000000000000000000000000000000000
33335333333335333338338338338338338333338333333338333333335833300000000000000000000000000000000000000000000000000000000000000000
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
33333333333333333773333773333333333333333333333333333333333333330000000000000000000000000000000000000000000000000000000000000000
33333333333333333333333333333333333333773333333333333373333300000000000000000000000000000000000000000000000000000000000000000000
30000000000330000000000330007700000330777000000330000770000300000000000000000000000000000000000000000000000000000000000000000000
30000000000330000000000330007700000330077000000330000770000300000000000000000000000000000000000000000000000000000000000000000000
30000000000330000000000337700770000330077700000330000770000300000000000000000000000000000000000000000000000000000000000000000000
30007767777730007770000337770670000330007707700330000770000300000000000000000000000000000000000000000000000000000000000000000000
30d77777777730d77777700330677067007730776677700330777770770300000000000000000000000000000000000000000000000000000000000000000000
30d77dd7600330d77dd7700377066766777737777677000330777677770300000000000000000000000000000000000000000000000000000000000000000000
30d77777777730d77777700377776666776337767677000330767677700300000000000000000000000000000000000000000000000000000000000000000000
30d77dd7777730d77dd7700330666666660330676777000330666776000300000000000000000000000000000000000000000000000000000000000000000000
30d67777700330d67777600330006666dd033006666d000330667660000300000000000000000000000000000000000000000000000000000000000000000000
333366663333333366663333333333ddd333333366d33333333dddd3333300000000000000000000000000000000000000000000000000000000000000000000
33333333333333333333333333333999933333aaaaa3333aaaaa3300000000000000000000000000000000000000000000000000000000000000000000000000
3000000033000000033000000033999999033aaa9a7a33aa9a97a300000000000000000000000000000000000000000000000000000000000000000000000000
300000003300990003aa0000003999999993aaa99977aaa9a9797a00000000000000000000000000000000000000000000000000000000000000000000000000
30aa00003309999003aaaa00003999999993aaa9aa77aaa9aaa97a00000000000000000000000000000000000000000000000000000000000000000000000000
3000aa00330999900330aaaa003999999993aaa999aaaaaa9a9aaa00000000000000000000000000000000000000000000000000000000000000000000000000
3000000033009900033000aaaa39999999939aaa9aaa99aaa9aaa900000000000000000000000000000000000000000000000000000000000000000000000000
300000003300000003300000aa339999990399aaaaa9999aaaaa9900000000000000000000000000000000000000000000000000000000000000000000000000
30000000330000000330000000330999900339499999339499999300000000000000000000000000000000000000000000000000000000000000000000000000
33333333333333333333333333333333333333494943333494943300000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003335555555333
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000051111111115511111111153005555565003
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011555555511115555555113005555565003
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015511111551155111115513005555565003
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015111511151151115111513005555555003
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015115151151151155511513005555555003
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015111511151151115111511008888888001
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000015511111551155111115515555555555555
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000011555555511115555555113555555555553
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005111111111551111111115333333f333333
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000004444444444884448444444344443000090f00003
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000880000088888b088f44880308843000090f00003
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000008188888188883b88884880088843009094f09003
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000480000084bb31338844088380043094499944903
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000004800800844088833b43303830043009977799003
0000000000000000000000000000000000000000000000000000000000000000000031111333333333111130480000084438f8b0044088300043097777777903
00000000000000000000000000000000000000000000000000000000000000000000111551000000015555108188888183b888bb0440880030439777777777f3
0000000000000000000000000000000000000000000000000000000000000000000011115555555555555110884444488444b3444444444443439777777777f3
0000000000000000000000000000000000000000000000000000000000000000000011111155555555511110000000000000000000000000000977777777777f
0000000000000000000000000000000000000000000000000000000000000000000033331111111111133330000000000000000000000000000977777777777f
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009777777777779
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009777777777779
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009777777777779
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009777777777779
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003977777777793
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003977777777793
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003047777777403
000000000000000000000000000000000000000000000000000000000005333333333333333000000000000000000000000000000000000000039949777949f3
00000000000000000000000000000000000000000000000000000000000555511111111111100000000000000000000000000000000000000003944999994493
00000000000000000000000000000000000000000000000000000000000111111110000000333333633333333333333333363333333333333333099494949903
00000000000000000000000000000000000000000000000000000000000555510000000000330007770033000000003300777000330677776033000094900003
00000000000000000000000000000000000000000000000000000000000550000000000000330077577033677777763307777700330757777033000099900003
00000000000000000000000000000000000000000000000000000000000510000000011111330777777733777777573377777770330777777033000009000003
00000000000000000000000000000000000000000000000000000000000510000000155555137775577763777557773675755777330775577033000009000003
00000000000000000000000000000000000000000000000000000000000110000000151115167775577733777557773377755757630775577033000009000003
00000000000000000000000000000000000000000000000000000000000110000000151515137777777033757777773307777777330777777033000099f00003
00000000000000000000000000000000000000000000000000000000000111111111155555130775770033677777763300777770330777757033000099f00003
00000000000000000000000000000000000000000000000000000000000110000000155155130077700033000000003300077700330677776033000049900003
00000000000000000000000000000000000000000000000000000000000113333333115551133336333333333333333333336333333333333333333334333333
00000000000000000000000000000000000000000000000000033336663333333366633333333666333333337773333333376633333333cbb333333336663333
000000000000000000000000000000000000000000000000000306666666033066666660330777777703307777776033067667770330accbbee0330666666603
00000000000000000000000000000000000000000000000000037777777773377766677733ddd777ddd337777766773367677676733aaccbbee83377777dd773
0000000000000000000000000000000000000000000000000003ddd777ddd3377777777733777777777337776677663377676767633aaccbbee833dd77777d73
0000000000000000000000000000000000000000000000000007777777777777dd777dd7777d77777d7777667766666676766766776aaccbbee8877777777777
00000000000000000000000000000000000000000000000000077d77777d777776d7d67777d7d777d7d766776666677767677677666aaccbbee887d77777d776
0000000000000000000000000000000000000000000000000007d7d777d7d7777777777777777777777777666667777677676766776aaccbbee88d7d777d7d76
00000000000000000000000000000000000000000000000000077d77777d777d7d777d7d777ddddddd7766666777776767767777676aaccbbee887d77777d777
0000000000000000000000000000000000000000000000000007777777777777d77777d7777ddddddd7766677777667776776767766aaccbbee8877777777777
00000000000000000000000000000000000000000000000000077d77777d777777777777777ddddddd776777776677767676767766111ee11cc117777dd77777
01230000000000000000000000000000000000000000000000037ddddddd73377ddddd773377ddddd7733777667777336766676673311ee11cc1337dddd77773
45670000000000000000000000000000000000000000000000036777777763377d777d7733667777766337667777773376776767633ddddddddd336777777763
89a300000000000000000000000000000000000000000000000306677766033077777770330666666603307777777033076776670330ddddddd0330667776603
cdef0000000000000000000000000000000000000000000000033336663333333366633333333666333333337773333333376733333333ddd333333336663333

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


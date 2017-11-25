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

symbols:
	up:		”
	down:	ƒ
	left:	‹
	right:	‘

starting symbols: 6838
after a bit of work: 6206
after more work: 5305
]]

-- useful noop function
function noop() end

-- global constants
local color_ramp_str="751000007d5100007e82100076b351007f94210076d510007776d51077776d1077e821007fa9421077fa9410776b3510776cd510776d510077fe8210777f9410"
local color_ramps={}
local rainbow_color

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
		y=-25,
		up_pressed=false,
		down_pressed=false,
		left_pressed=false,
		right_pressed=false,
		button_presses=0,
		update=function(self)
			self:check_button_press("up",2)
			self:check_button_press("down",3)
			self:check_button_press("left",0)
			self:check_button_press("right",1)
		end,
		draw=function(self)
			local fade=4
			if self.frames_to_death>0 then
				fade=mid(6,6-flr(self.frames_to_death/15),4)
			end
			color(color_ramps[6][fade])
			print("press",self.x-9,self.y-18)
			print("to move",self.x-13,self.y+14)
			print("”",self.x-3,self.y-9,self:choose_color("up",fade))
			print("‹",self.x-11,self.y-2,self:choose_color("left",fade))
			print("‘",self.x+5,self.y-2,self:choose_color("right",fade))
			print("ƒ",self.x-3,self.y+5,self:choose_color("down",fade))
		end,
		on_death=function(self)
			spawn_magic_tile(50)
		end,
		check_button_press=function(self,dir,index)
			if btn(index) and not self[dir.."_pressed"] then
				self[dir.."_pressed"]=true
				self.button_presses+=1
				self.frames_to_death=45*(5-self.button_presses)
			end
		end,
		choose_color=function(self,dir,fade)
			local color=ternary(self[dir.."_pressed"],12,6)
			return color_ramps[color][fade]
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
			if btnp(0) then
				self:queue_move("left")
			elseif btnp(1) then
				self:queue_move("right")
			elseif btnp(2) then
				self:queue_move("up")
			elseif btnp(3) then
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
			freeze_frames=4
			screen_shake_frames=max(screen_shake_frames,12)
		end,
		stun=function(self)
			-- self:cancel_move(self:col(),self:row())
			self.invincibility_frames=60
			self.stun_frames=19
			player_health:lose_heart()
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
				sprite_x=ternary(self.teeter_frames<=2,52,40) -- 64)
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
	player_health={
		visible=false,
		hearts=3,
		anim=nil,
		anim_frames=0,
		x=63,
		y=122,
		is_user_interface=true,
		update_priority=0,
		gain_heart=function(self)
			if self.hearts<4 then
				self.hearts+=1
				self.anim="gain"
				self.anim_frames=10
			end
		end,
		lose_heart=function(self)
			if self.hearts>0 then
				self.hearts-=1
				self.anim="lose"
				self.anim_frames=20
			end
			if self.visible then
				self.visible=false
				freeze_frames=20
			end
			return self.hearts<=0
		end,
		update=function(self)
			if decrement_counter_prop(self,"anim_frames") then
				self.anim=nil
			end
		end,
		draw=function(self)
			if self.visible then
				palt(3,true)
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
		end
	},
	boss_health={
		visible=false,
		health=0,
		visible_health=0,
		rainbow_frames=0,
		phase=0,
		x=63,
		y=5,
		is_user_interface=true,
		update_priority=0,
		gain_health=function(self,health)
			self.health=mid(0,self.health+health,60)
			self.rainbow_frames=15+(self.health-self.visible_health)
			if self.phase==0 then
				if self.health>=20 and not self.visible then
					self.visible=true
				end
				if self.health>=40 then
					boss.rainbow_frames=self.rainbow_frames
				end
				if self.health>=50 and not boss.visible then
					boss.visible=true
				end
				if self.health>=60 then
					-- boss:schedule(55,"intro")
				end
			end
		end,
		next_phase=function(self)
			self.phase+=1
			self.health=0
		end,
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
				if self.rainbow_frames>0 then
					pal2(5,16)
				end
				rect(self.x-30,self.y-3,self.x+30,self.y+3,5)
				rectfill(self.x-30,self.y-3,self.x+mid(-30,-31+self.visible_health,29),self.y+3,5)
			end
		end
	},
	magic_tile_spawn={
		frames_to_death=10,
		draw=function(self)
			if self.frames_to_death<=10 then
				local d=self.frames_to_death
				rect(self.x-4-d,self.y-3-d,self.x+4+d,self.y+3+d,ternary(self.frames_alive<4,5,6))
			end
		end,
		on_death=function(self)
			screen_shake_frames=max(screen_shake_frames,1)
			spawn_entity("magic_tile",self.x,self.y)
			make_sparks(self.x,self.y,0,-3,4,"rainbow",0.3)
		end
	},
	magic_tile={
		hurtbox_channel=2,
		render_layer=3,
		draw=function(self)
			local fade=mid(1,flr(self.frames_alive/2),4)
			local color=color_ramps[rainbow_color][fade]
			local background_color=color_ramps[1][fade]
			rectfill(self.x-4,self.y-3,self.x+4,self.y+3,background_color)
			rect(self.x-4,self.y-3,self.x+4,self.y+3,color)
			rect(self.x-2,self.y-1,self.x+2,self.y+1,color)
		end,
		on_hurt=function(self)
			freeze_frames=1
			screen_shake_frames=max(screen_shake_frames,3)
			spawn_entity("magic_tile_fade",self.x,self.y)
			make_sparks(self.x,self.y,0,-10,30,"rainbow",1)
			boss_health:gain_health(10)
			if boss_health.health<60 then
				spawn_magic_tile(100-min(self.frames_alive,30)) -- 30 frame grace period
			end
			self:die()
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
			local mirrored_directions={
				left="right",
				right="left",
				up="up",
				down="down"
			}
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
		update=function(self)
			if self.frames_alive>self.bloom_frames+3 then
				self.hitbox_channel=0
			elseif self.frames_alive==self.bloom_frames then
				self.hitbox_channel=1 -- player
				self.frames_to_death=35
				local i
				for i=1,2 do
					spawn_entity("flower_petal",self.x,self.y-5,{
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
		x=40,
		y=-28,
		hitbox_channel=1, -- player
		rainbow_frames=0,
		expression=4,
		-- laser_charge_frames=0,
		-- laser_preview_frames=0,
		-- laser_fire_frames=0,
		-- hover_frames=0,
		-- hover_dir=nil,
		-- actions={},
		init=function(self)
			self.left_hand=spawn_entity("magic_mirror_hand",self.x-18,self.y+5)
			self.right_hand=spawn_entity("magic_mirror_hand",self.x+18,self.y+5,{is_right_hand=true,dir=1})
		end,
		update=function(self)
			decrement_counter_prop(self,"rainbow_frames")
			-- decrement_counter_prop(self,"laser_preview_frames")
			-- decrement_counter_prop(self,"laser_fire_frames")
			-- if decrement_counter_prop(self,"hover_frames") then
			-- 	self.vx=0
			-- 	self.vy=0
			-- end
			self:apply_move()
			-- if self.hover_frames>0 then
			-- 	if self.x<=5 then
			-- 		self.hover_dir=1
			-- 	elseif self.x>=75 then
			-- 		self.hover_dir=-1
			-- 	end
			-- 	self.vx=2*self.hover_dir
			-- 	self.vy=0
			-- end
			self:apply_velocity()
			-- if self.laser_charge_frames>0 then
			-- 	decrement_counter_prop(self,"laser_charge_frames")
			-- 	local angle=rnd_int(1,360)
			-- 	spawn_entity("charge_particle",self.x+20*cos(angle/360),self.y+20*sin(angle/360),{
			-- 		target_x=self.x,
			-- 		target_y=self.y,
			-- 		color=7
			-- 	})
			-- end
		end,
		draw=function(self)
			pal2(3)
			-- draw mirror
			sspr2(115,84,13,30,self.x-6,self.y-12)
			-- draw face
			if self.expression>0 then
				sspr2(51+11*self.expression,114,11,14,self.x-5,self.y-7,false,self.expression==5 and (self.frames_alive)%4<2)
			end
			-- draw top hat
			if self.is_wearing_top_hat then
				sspr2(115,75,13,9,self.x-6,self.y-15)
			end
			-- 	-- draw laser
			-- 	if self.laser_preview_frames%2==1 then
			-- 		self:reset_colors()
			-- 		line(self.x,self.y+7,self.x,60,14)
			-- 	end
			-- 	if self.laser_fire_frames>0 then
			-- 		self:reset_colors()
			-- 		rect(self.x-5,self.y+4,self.x+5,60,14)
			-- 		rect(self.x-4,self.y+4,self.x+4,60,15)
			-- 		rectfill(self.x-3,self.y+4,self.x+3,60,7)
			-- 		-- line(self.x-4,self.y,self.x-4,60,7)
			-- 		-- line(self.x,1,self.x,39,14)
			-- 	end
		end,
		is_hitting=function(self,entity)
			return false
			-- return self.laser_fire_frames>0 and entity:col()==self:col()
		end,
		-- highest-level commands
		intro=function(self)
			if true then
				self:set_expression(1)
				self:don_top_hat()
				self.right_hand:appear()
				self.right_hand:set_pose(4)
				self.left_hand:appear()
				self.left_hand:grab_mirror_handle(self)
				return self:promise(20)
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
					:and_then(self,"don_top_hat"):and_then(10)
			end
		end,
		decide_next_action=function(self)
			return self:throw_cards()
				:and_then(function()
					-- called this way so that the progressive decide_next_action
					--   calls don't result in an out of memory exception
					self:decide_next_action()
				end)
		end,
		-- medium-level commands
		throw_cards=function(self)
			local promise=self:promise()
			if self.left_hand.held_mirror then
				promise=promise:and_then(self.left_hand,"release_mirror")
			end
			if self.right_hand.held_mirror then
				promise=promise:and_then(self.right_hand,"release_mirror")
			end
			return promise
				:and_then(function()
					return all_promises(self.left_hand:throw_cards(),self.right_hand:throw_cards())
				end)
				:and_then(self,10)
		end,
		-- lowest-level commands
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
		-- shoot_lasers=function(self)
			-- local hover_frames=25
			-- local laser_fire_frames=65
			-- self:set_expression(5)
			-- self:schedule(6,"move_to_player_col")
			-- self:schedule(16,"shoot_laser")
			-- local f=16+laser_fire_frames
			-- local i
			-- for i=1,2 do
			-- 	self:schedule(f,"hover",hover_frames)
			-- 	f+=hover_frames
			-- 	self:schedule(f,"shoot_laser")
			-- 	f+=laser_fire_frames
			-- end
		-- end,
		-- hover=function(self,frames,dir)
			-- self.hover_frames=frames
			-- self.hover_dir=dir or self.hover_dir or 1
		-- end,
		-- shoot_laser=function(self)
			-- local laser_charge_frames=14
			-- local preview_frames=12
			-- local laser_fire_frames=25
			-- self:set_expression(4)
			-- self:charge_laser(laser_charge_frames)
			-- self:schedule(laser_charge_frames,"preview_laser",preview_frames+laser_fire_frames+4)
			-- self:schedule(laser_charge_frames+preview_frames,"fire_laser",laser_fire_frames)
			-- self:schedule(laser_charge_frames+preview_frames,"set_expression",0)
			-- self:schedule(laser_charge_frames+preview_frames+laser_fire_frames,"set_expression",4)
		-- end,
		-- charge_laser=function(self,frames)
			-- self.laser_charge_frames=frames
		-- end,
		-- preview_laser=function(self,frames)
			-- self.laser_preview_frames=frames
		-- end,
		-- fire_laser=function(self,frames)
			-- self.laser_fire_frames=frames
		-- end,
		-- reset_state=function(self,held_hand)
			-- if not self.left_hand.held_mirror or not self.right_hand.held_mirror then
			-- 	self:set_held_hands(held_hand or "left")
			-- end
			-- if self.expression!= 1 then
				-- self:schedule(5,"set_expression",5)
				-- self:schedule(16,"set_expression",1)
			-- end
			-- self:schedule(15,"move_to_home")
			-- self:schedule(45,"set_held_hands",held_hand)
		-- end,
		-- move_to_home=function(self)
			-- lasts 30 frames
			-- self:move(40,-28,30,{easing=ease_in,relative=false})
			-- if not self.left_hand.held_mirror then
			-- 	self.left_hand:move_to_home(40,-28)
			-- end
			-- if not self.right_hand.held_mirror then
			-- 	self.right_hand:move_to_home(40,-28)
			-- end
		-- end,
		-- set_held_hands=function(self,held_hand)
			-- lasts 10 frames
			-- if self.left_hand.held_mirror and held_hand!="left" then
			-- 	self.left_hand:release_mirror()
			-- elseif not self.left_hand.held_mirror and held_hand=="left" then
			-- 	self.left_hand:grab_mirror(self)
			-- end
			-- if self.right_hand.held_mirror and held_hand!="right" then
			-- 	self.right_hand:release_mirror()
			-- elseif not self.right_hand.held_mirror and held_hand=="right" then
			-- 	self.right_hand:grab_mirror(self)
			-- end
		-- end,
		-- conjure_flowers=function(self)
			-- local increment=3
			-- local time_to_bloom=70
			-- self.left_hand:set_pose(1)
			-- self.left_hand:move(self.x-15,self.y,20,{easing=ease_in})
			-- self.right_hand:set_pose(1)
			-- self.right_hand:move(self.x+15,self.y,20,{easing=ease_in})
			-- self:schedule(10,"set_expression",2)
			-- self:schedule(30,"spawn_flowers",increment,time_to_bloom)
			-- self:schedule(29+time_to_bloom,"set_expression",3)
			-- self.left_hand:schedule(29+time_to_bloom,"set_pose",4)
			-- self.right_hand:schedule(29+time_to_bloom,"set_pose",4)
		-- end,
		-- spawn_flowers=function(self,increment,time_to_bloom)
			-- local restricted_col=rnd_int(0,3)
			-- local restricted_row=rnd_int(0,4)
			-- local flowers={}
			-- local i=rnd_int(0,increment-1)
			-- while i<40 do
			-- 	local c=i%8
			-- 	local r=flr(i/8)
			-- 	if (c!=restricted_col and (7-c)!=restricted_col) or r!=restricted_row then
			-- 		add(flowers,{
			-- 			x=10*c+5,
			-- 			y=8*r+4,
			-- 			bloom_frames=time_to_bloom,
			-- 			flipped=(rnd()<0.5),
			-- 			color=rnd_from_list({8,12,9,14})
			-- 		})
			-- 	end
			-- 	i+=rnd_int(1,increment)
			-- end
			-- shuffle_list(flowers)
			-- for i=1,#flowers do
			-- 	flowers[i].hidden_frames=i
			-- 	spawn_entity("flower_patch",flowers[i])
			-- end
		-- end,
		-- move_to_player_col=function(self,a,b,c,d)
			-- 20 frames
			-- self:move(10*player:col()-5,-20,20,{easing=ease_in,immediate=true})
		-- end,
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
			self:set_pose(3)
			return self:move(15*self.dir,-7,25,ease_in,nil,true)
		end,
		appear=function(self)
			self.visible=true
			return self:poof()
		end,
		-- lowest-level commands
		move_to_row=function(self,row)
			return self:promise("set_pose",3)
				:and_then("move",40+50*self.dir,8*row-4,20,ease_in_out,{10*self.dir,-10,10*self.dir,10})
				:and_then("set_pose",2)
		end,
		set_pose=function(self,pose)
			self.pose=pose
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
	spark={
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
			-- local c=self.color
			-- if c=="rainbow" then
			-- 	c=rainbow[1+flr(scene_frame/4)%#rainbow]
			-- end
			-- local fade=mid(1,self.frames_alive+1,4)
			-- if self.frames_to_death<=5 then
			-- 	fade=mid(5,7-flr(self.frames_to_death/2),6)
			-- end
			-- color(color_ramps[c][fade])
			if self.color=="rainbow" then
				color(rainbow_color)
			else
				local fade=mid(1,self.frames_alive+1,4)
				if self.frames_to_death<=5 then
					fade=mid(5,7-flr(self.frames_to_death/2),6)
				end
				color(color_ramps[self.color][fade])
			end
			line(self.prev_x,self.prev_y,self.x,self.y)
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
			-- player_health:gain_heart()
			-- make_sparks(self.x,self.y,0,-3,6,8,0.3)
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

-- local skip_frames=0
function _update()
	-- skip_frames=increment_counter(skip_frames)
	-- if skip_frames%1>0 then return end
	-- update promises
	local num_promises,i=#promises
	for i=1,num_promises do
		promises[i]:update()
	end
	filter_list(promises,function(promise)
		return not promise.finished
	end)
	-- call the update function of the current scene
	if freeze_frames>0 then
		freeze_frames=decrement_counter(freeze_frames)
	else
		screen_shake_frames=decrement_counter(screen_shake_frames)
		scene_frame=increment_counter(scene_frame)
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
	heart=spawn_entity("heart",45,4)
	-- get to the good part
	boss.visible=true
	boss_health.visible=true
	boss:intro():and_then("decide_next_action")
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
	camera()
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
	local promise,promises,num_finished=make_promise(),{...},0
	foreach(promises,function(promise2)
		promise2:and_then(function()
			num_finished+=1
			if num_finished==#promises then
				promise:finish()
			end
		end)
	end)
	return promise
end

function spawn_magic_tile(frames_to_death)
	spawn_entity("magic_tile_spawn",10*rnd_int(1,8)-5,8*rnd_int(1,5)-4,{frames_to_death=frames_to_death})
end

function make_sparks(x,y,vx,vy,num_sparks,color,speed_percent)
	local i
	for i=1,num_sparks do
		local angle=360*((i+rnd(0.7))/num_sparks)--rnd_int(0,360)
		local speed=speed_percent*rnd_int(7,15)
		local cos_angle=cos(angle/360)
		local sin_angle=sin(angle/360)
		spawn_entity("spark",x+5*cos_angle,y+5*sin_angle,{
			vx=speed*cos_angle+vx,
			vy=speed*sin_angle+vy,
			color=color,
			frames_to_death=rnd_int(13,19)
		})
	end
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
	sspr(x,y,width,height,x2,y2,width,height,flip_horizontal,flip_vertical)
	-- rect(x2,y2,x2+width-1,y2+height-1,8)
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
3ccccc33cc33333333333333cccc333333ccccc33333933cc3333333333333333333333cc3333333333333330000000000000000000000000000031111111113
cccccccccccccccc0330000cccccc3000ccccccc30008dccccc3300000000003300000cccc0330000c0000030000000000000000000000000000011111111111
cccc1c1cccc1111c1c3000ccc11c13000cccc1c130000cccccc33000c11cccc3300000cccc0330000c0c00030000000000000000000000000000011111101011
cdcc1c1cddd1111c1c30cddcc11c13000dccc1c13000dcc1c1cc30ccc11111cc300000cc1c033000ccccc0030000000000000000000000000000011111110111
cccccccccccccccccc300cccccccc3000ccccccc300ddcc1c1cc3dccddcccccc300000cc1c033d0ccccccc030000000000000000000000000000011111101011
ddcccccddcdddd00033000ddccddc3000ddcccdc3000ddccccc3dddccccccdd3300000dccc0330dcccc11c0d0000000000000000000000000000011111111111
ddddddddddd0000003300ddddddd3300dddddddd30000ddcccd3dddddddd0003300000ddcc0330ccc1c11cd30000000000000000000000000000031111111113
3d333d33d33333333333333333d33333333333d3333333d33398333333d333333333333dd3333000ccccccc3000000000000000000000000000000ddddd33333
3ccccc33333333c33333333ccccc333333ccccc33333ccccc33333333333333333333333333330dcccccc003000000000000000000000000000001d0d0d00101
ccccccc300000ccc0330000ccccc33000ccccccc390ccccccc09300000000003300ccccccc03300ddddddd03000000000000000000000000000003d0d0d00013
ccccccc300000ccc033000ccccccc3000ccccccc30dcccccccd330d0000000d330ccccccccc33333d333d3330000000000000000000000000000015ddd500101
dcccccd300000ccc033000ccccccc3000dcccccd380cdddddc0830dcccccccd330ccdddddcc3000000000000000000000000000000000000000000ddddd33333
ccccccc30000ccccc33000dcccccd3000ccccccc300ddddddd0330dcccccccd3300ddddddd030000000000000000000000000000000000000000000000000000
cdddddc30000dcccd33000dcdddcd3000cdddddc300ddddddd0330cdddddddc33000000000030000000000000000000000000000000000000000000000000000
ddddddd30000dcccd33000ddddddd3000ddddddd3000ddddd00330ddddddddd33000000000030000000000000000000000000000000000000000000000000000
3d000d330000cdddc33000ddddddd30000000d0330000d000003300ddddddd033000000000030000000000000000000000000000000000000000000000000000
30000033000ddddddd3000000ddd3300000000033000000000033000000000033000000000030000000000000000000000000000000000000000000000000000
30000033000ddddddd30000000d03300000000033000000000033000000000033000000000030000000000000000000000000000000000000000000000000000
333333333333d333d333333333d33333333333333333333333333333333333333333333333330000000000000000000000000000000000000000000000000000
333333333333ccccc333333333333333333333333333333333333333333333333333333333330000000000000000000000000000000000000000000000000000
30000033000ccccccc3000000c003300000000033000000000033000000000033000000000030000000000000000000000000000000000000000000000000000
30000033000cc1c1cc300000cc0c3300000000033000000000033000000000033000000000030000000000000000000000000000000000000000000000000000
3ccccc330000c1c1c330000ccccc330000ccccc330000000000330000ccc00033000000000030000000000000000000000000000000000000000000000000000
ccccccc30000c1c1d33000cc1c1cc3000ccccccc3000ccccc0033000c1c1c0033000000000030000000000000000000000000000000000000000000000000000
cc1c1cc30000c1c1d33000cc1c1cd3000cc1c1cc390ccccccc083000c1c1c0033000000000030000000000000000000000000000000000000000000000000000
dc1c1cd30000d1c1d33000cd1c1cd3000cc1c1cd30dcccccccd330ddc1c1cd033000000000030000000000000000000000000000000000000000000000000000
ccccccc30000ddccc33000ddccccc3000cdccccc380ccccccc0930dcc1c1cdd3300ccccccc030000000000000000000000000000000000000000000000000000
dcccccd300000ddd033000dcccccc3000dcccccc300cc1c1cc0330ccc1c1ccd330ccccccccc30000000000000000000000000000000000000000000000000000
ddddddd300000ddd033000ddddddd3000ddddddd300cc1c1cc0330ccc1c1ccc330dc11c11cd30000000000000000000000000000000000000000000000000000
3d333d33333333d33333333d3333333333d333333333ccccc3333333dddddd33333dcccccd330000000000000000000000000000000000000000000000000000
33333333333333333383333333883333333833333333333333333338833333300000000000000000000000000000000000000000000000000000000000000000
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
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000004444444444444444444e84448443000090f00003
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000880000088408000804e88008ee43000090f00003
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000008088888084880008848883088e83009094f09003
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000004800000844008380044b30b38843094499944903
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000480080084400383004408e830043009977799003
000000000000000000000000000000000000000000000000000000000000000000003111133333333311113048000008440883000443eee0b043097777777903
0000000000000000000000000000000000000000000000000000000000000000000011155100000001555510808888808400800004408e8000439777777777f3
0000000000000000000000000000000000000000000000000000000000000000000011115555555555555110884444488444444444444b4444439777777777f3
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
0000000000000000000000000000000000000000000000000000000000000033337773333333366633333333777333333337773333333376633333333cbb3333
00000000000000000000000000000000000000000000000000000000000000307777777033066666660330777777703307777776033067667770330accbbee03
0000000000000000000000000000000000000000000000000000000000000037777777773366666666633ddd777ddd337777766773367677676733aaccbbee83
000000000000000000000000000000000000000000000000000000000000003ddd777ddd3377777777733777777777337776677663377676767633aaccbbee83
000000000000000000000000000000000000000000000000000000000000007777777777777dd777dd7777d77777d7777667766666676766766776aaccbbee88
0000000000000000000000000000000000000000000000000000000000000077d77777d777777d7d77777d7d777d7d766776666677767677677666aaccbbee88
000000000000000000000000000000000000000000000000000000000000007d7d777d7d7777777777777777777777777666667777677676766776aaccbbee88
0000000000000000000000000000000000000000000000000000000000000077d77777d777d7d777d7d777ddddddd7766666777776767767777676aaccbbee88
000000000000000000000000000000000000000000000000000000000000007777777777777d77777d7777ddddddd7766677777667776776767766aaccbbee88
0000000000000000000000000000000000000000000000000000000000000077d77777d777777777777777ddddddd776777776677767676767766111ee11cc11
0123000000000000000000000000000000000000000000000000000000000037ddddddd73377ddddd773377ddddd7733777667777336766676673311ee11cc13
4567000000000000000000000000000000000000000000000000000000000036777777763377d777d7733677777776337667777773376776767633ddddddddd3
89a30000000000000000000000000000000000000000000000000000000000306677766033077777770330667776603307777777033076776670330ddddddd03
cdef000000000000000000000000000000000000000000000000000000000033336663333333366633333333666333333337773333333376733333333ddd3333

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


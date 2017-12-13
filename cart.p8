pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
--[[
coordinates:
  +x is right, -x is left
  +y is towards the player, -y is away from the player
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

todo:
	player pain animation
	green mirror doesn't have uggo pain face when lasering
	summon flowers phase change animation
	bump into coins to destroy them
	phase 4 throw coins alternating
	more coin throw pause but faster throw
	death animation
	title screen
	death screen
	victory screen
	sound effects + music
]]

-- useful noop function
function noop() end

-- global constants
local color_ramp_str="751000007d5100007e82100076b351007f94210076d510007776d51077776d1077e821007fa9421077fa9410776b3510776cd510776d510077fe8210777f9410"
local color_ramps={}

-- global config vars
local beginning_phase=1
local one_hit_ko=true
local tiles_collected

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
local player_reflection
local boss
local boss_reflection
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
					if self.frames_to_death<=0 then
						self.frames_to_death=180-30*self.num_buttons_pressed
					else 
						self.frames_to_death=min(self.frames_to_death,180-30*self.num_buttons_pressed)
					end
					self.button_presses[i]=true
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
			local move=self.movement
			if move then
				move.frames+=1
				local t=move.easing(move.frames/move.duration)
				local i
				self.vx,self.vy=-self.x,-self.y
				for i=0,3 do
					local m=ternary(i%3>0,3,1)*t^i*(1-t)^(3-i)
					self.vx+=m*move.bezier[2*i+1]
					self.vy+=m*move.bezier[2*i+2]
				end
				if move.frames>=move.duration then
					self.x,self.y,self.vx,self.vy,self.movement=move.final_x,move.final_y,0,0 -- ,nil
				end
			end
		end,
		move=function(self,x,y,dur,easing,anchors,is_relative)
			local start_x,start_y,end_x,end_y=self.x,self.y,x,y
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
				bezier={start_x,start_y,
					start_x+anchors[1],start_y+anchors[2],
					end_x+anchors[3],end_y+anchors[4],
					end_x,end_y}
			}
			return max(0,dur-1)
		end,
		cancel_move=function(self)
			self.vx,self,vy,self.movement=0,0 -- ,nil
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
			self:check_inputs()
			-- apply moves that were delayed from teetering/stun
			if self.next_step_dir and not self.step_dir then
				self:step(self.next_step_dir)
			end
			-- actually move
			self.prev_col,self.prev_row=self:col(),self:row()
			if self.stun_frames<=0 then
				self.vx,self.vy=0,0
				self:apply_step()
				self:apply_velocity()
				local col,row=self:col(),self:row()
				if self.prev_col!=col or self.prev_row!=row then
					-- teeter off the edge of the earth if the player tries to move off the map
					if col!=mid(1,col,8) or row!=mid(1,row,5) then
						self:undo_step()
						self.teeter_frames=11
					end
					-- bump into an obstacle or reflection
					if is_tile_occupied(col,row) or (player_reflection and (self.prev_col<5)!=(col<5)) then
						self:bump()
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
				spritesheet_x=66
				if self.bump_frames<=0 then
					local c=ternary(self.teeter_frames%4<2,8,9)
					pal2(c)
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
				spritesheet_x,spritesheet_y,spritesheet_height,dx,dy,flipped=77,0,10,5,8,self.stun_frames%6>3
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
		check_inputs=function(self)
			if btnp(0) then
				self:queue_step("left")
			elseif btnp(1) then
				self:queue_step("right")
			elseif btnp(2) then
				self:queue_step("up")
			elseif btnp(3) then
				self:queue_step("down")
			end
		end,
		bump=function(self)
			self:undo_step()
			self.bump_frames=11
			freeze_and_shake_screen(0,5)
		end,
		undo_step=function(self)
			self.x,self.y,self.step_frames,self.step_dir,self.next_step_dir=10*self.prev_col-5,8*self.prev_row-4,0 -- ,nil,nil
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
			self.invincibility_frames,self.stun_frames=60,19
			player_health:lose_heart()
		end
	},
	player_health={
		x=63,
		y=122,
		-- visible=false,
		hearts=4,
		-- anim=nil,
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
					sspr2(0,30,9,7,self.x+8*i-24,self.y-3)
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
						sspr2(9*sprite,30,9,7,self.x+8*i-24,self.y-3)
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
				freeze_and_shake_screen(9,0)
			end
		end
	},
	boss_health={
		x=63,
		y=5,
		-- visible=false,
		health=0,
		phase=0,
		visible_health=0,
		rainbow_frames=0,
		is_user_interface=true,
		update=function(self)
			decrement_counter_prop(self,"rainbow_frames")
			if self.health>=60 then
				self.visible_health=60
			elseif self.visible_health<self.health then
				self.visible_health+=1
			elseif self.visible_health>self.health then
				self.visible_health-=1
			end
		end,
		draw=function(self)
			if self.visible then
				local x,y=self.x,self.y
				rect(x-30,y-3,x+30,y+3,get_color(ternary(self.rainbow_frames>0,16,5)))
				rectfill(x-30,y-3,x+mid(-30,-31+self.visible_health,29),y+3)
			end
		end,
		gain_health=function(self)
			-- 6 to start -> 10 hp per
			-- 8 after that -> 8 hp per
			local health=ternary(one_hit_ko,60,ternary(self.phase<1,10,8))
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
			freeze_and_shake_screen(2,6)
			self.hurtbox_channel,self.frames_to_death=0,6
			spawn_particle_burst(self.x,self.y,30,16,10)
			boss_health:gain_health()
			on_magic_tile_picked_up(self)
		end
	},
	player_reflection={
		extends="player",
		update_priority=10,
		primary_color=11,
		secondary_color=3,
		eye_color=3,
		init=function(self)
			self:copy_player()
			spawn_entity("poof",self.x,self.y)
		end,
		update=function(self)
			local prev_col,prev_row=self:col(),self:row()
			self:copy_player()
			if (prev_col!=self:col() or prev_row!=self:row()) and is_tile_occupied(self:col(),self:row()) then
				player:bump()
				self:copy_player()
			end
		end,
		on_hurt=function(self,entity)
			player:on_hurt(entity)
			self:copy_player()
		end,
		copy_player=function(self)
			local mirrored_directions={left="right",right="left",up="up",down="down"}
			self.x,self.y,self.facing=80-player.x,player.y,mirrored_directions[player.facing]
			self.step_frames,self.stun_frames,self.teeter_frames=player.step_frames,player.stun_frames,player.teeter_frames
			self.bump_frames,self.invincibility_frames,self.frames_alive=player.bump_frames,player.invincibility_frames,player.frames_alive
		end
	},
	playing_card={
		-- vx,has_heart
		frames_to_death=75,
		hitbox_channel=1, -- player
		is_boss_generated=true,
		update=function(self)
			if self.frames_alive==50 and self.has_heart then
				spawn_entity("heart",self.x,self.y)
			end
			self:apply_velocity()
		end,
		draw=function(self)
			pal2(3)
			-- some cards are red
			if self.has_heart then
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
		is_boss_generated=true,
		hittable_frames=0,
		init=function(self)
			local c=rnd_int(1,3)
			self.color,self.accent_color,self.flipped=({8,14,15})[c],({15,7,14})[c],rnd()<0.5
		end,
		update=function(self)
			self.hitbox_channel=ternary(self.frames_to_death>self.hittable_frames,1,0) -- player
		end,
		draw=function(self)
			pal2(4)
			pal2(8,self.color)
			pal2(15,self.accent_color)
			sspr2(9*ceil(self.frames_to_death/34)+88,85,9,8,self.x-4,self.y-4,self.flipped)
		end,
		bloom=function(self)
			self.frames_to_death,self.hittable_frames=ternary(boss_health.phase==4,10,38),self.frames_to_death-3
			spawn_petals(self.x,self.y,2,self.color)
		end
	},
	coin={
		extends="movable",
		is_boss_generated=true,
		init=function(self)
			self.target_x,self.target_y=10*player:col()-5,8*player:row()-4
			self:promise_sequence(
				{"move",self.target_x+2,self.target_y,30,ease_out,{20,-30,10,-60}},2,
				function()
					self.hitbox_channel=5 -- player, coin
					self.occupies_tile=true
					freeze_and_shake_screen(2,2)
				end,
				{"move",-1,-4,3,ease_in,nil,true},2,
				{"move",-1,4,3,ease_out,nil,true},
				function()
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
			if self.frames_alive<36 then
				circfill(self.target_x,self.target_y,min(flr(self.frames_alive/7),4),2)
			end
			local sprite=0
			if self.frames_alive>20 then
				sprite=2
			end
			if self.frames_alive>=30 then
				sprite=ternary(self.has_heart,5,4)
			else
				sprite+=flr(self.frames_alive/3)%2
			end
			sspr(9*sprite,62,9,9,self.x-4,self.y-5)
		end,
		on_death=function(self)
			spawn_particle_burst(self.x,self.y,6,6,4)
			if self.has_heart then
				spawn_entity("heart",self.x,self.y)
			end
		end
	},
	particle={
		render_layer=10,
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
		render_layer=7,
		extends="movable",
		x=40,
		y=-28,
		home_x=40,
		home_y=-28,
		expression=4,
		laser_charge_frames=0,
		laser_preview_frames=0,
		idle_mult=0,
		idle_x=0,
		idle_y=0,
		visible=false,
		init=function(self)
			self.coins={}
			self.flowers={}
			self.left_hand=spawn_entity("magic_mirror_hand",self.x-18,self.y+5,{mirror=self,is_reflection=self.is_reflection})
			self.right_hand=spawn_entity("magic_mirror_hand",self.x+18,self.y+5,{mirror=self,is_right_hand=true,dir=1,is_reflection=self.is_reflection})
		end,
		update=function(self)
			if self.is_idle then
				self.idle_mult=min(self.idle_mult+0.05,1)
			else
				self.idle_mult=max(0,self.idle_mult-0.05)
			end
			self.idle_x=self.idle_mult*3*sin(self.frames_alive/60)
			self.idle_y=self.idle_mult*2*sin(self.frames_alive/30)
			decrement_counter_prop(self,"laser_charge_frames")
			decrement_counter_prop(self,"laser_preview_frames")
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
			local x,y=self.x+self.idle_x,self.y+self.idle_y
			if self.is_reflection then
				local i
				for i=1,15 do
					pal2(i,3)
				end
				pal2(7,11)
				pal2(6,11)
			end
			pal2(3)
			if self.visible then
				-- draw mirror
				sspr2(115,84,13,30,x-6,y-12)
				-- draw face
				if self.expression>0 then
					sspr2(29+11*self.expression,114,11,14,x-5,y-7,false,self.expression==5 and (self.frames_alive)%4<2)
				end
			end
			if boss_health.rainbow_frames>0 then
				if not self.is_reflection then
					local i
					for i=1,15 do
						pal2(i,16)
					end
					if self.expression>0 and self.expression!=5 and self.expression!=4 then
						pal2(13,16,-1)
					end
					pal2(3)
				end
				sspr2(117,114,11,14,x-5,y-7,false,self.expression==5 and (self.frames_alive)%4<2)
				if not self.is_reflection then
					pal()
					pal2(3)
				end
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
		intro=function(self)
			return self:promise_sequence(
				50,
				{self.left_hand,"appear"},30,
				{"set_pose",4},6,
				{"set_pose",5},6,
				{"set_pose",4},6,
				{"set_pose",5},6,
				{"set_pose",4},10,
				{self.right_hand,"appear"},15,
				"grab_mirror_handle",5,
				{self,"set_expression",5},33,
				{"set_expression",6},25,
				{"set_expression",5},33,
				{"set_expression",1},30,
				{function()
					self.left_hand:tap_mirror(self)
				end},10,
				"don_top_hat",30)
		end,
		skip_to_fight=function(self)
			self:set_expression(1)
			self:don_top_hat()
			self.right_hand:appear()
			self.left_hand:appear()
			return self:promise(5)
		end,
		decide_next_action=function(self)
			local promise=self:promise(1)
			if boss_health.phase==1 then
				local r=2*rnd_int(0,2)+1
				promise=self:promise_sequence(
					{"set_held_state","right"},
					{"throw_cards","left",r},
					{"return_to_ready_position",nil,"left"},
					{"throw_cards","right",r},
					{"return_to_ready_position",nil,"left"},
					"shoot_lasers",
					{"return_to_ready_position",nil,"right"})
			elseif boss_health.phase==2 then
				promise=self:promise_sequence(
					{"conjure_flowers",3},
					"return_to_ready_position",
					{"throw_cards",nil,rnd_int(1,5)},
					"return_to_ready_position",
					"despawn_coins",
					{"throw_coins",3},
					"return_to_ready_position",
					"shoot_lasers",
					"return_to_ready_position")
			elseif boss_health.phase==3 then
				-- todo 3 repeated batches of flowers
				promise=self:promise_sequence(
					"shoot_lasers",
					"return_to_ready_position",
					{"throw_cards",nil,rnd_int(1,5)},
					"return_to_ready_position",
					{"conjure_flowers",3},
					"return_to_ready_position",
					"despawn_coins",
					{"throw_coins",3},
					"return_to_ready_position")
			elseif boss_health.phase==4 then
				promise=self:promise_parallel(
					{self,"set_held_state",nil},
					{boss_reflection,"set_held_state",nil})
					:and_then(function()
						boss_reflection:promise_sequence(
							"return_to_ready_position",
							32,
							{"conjure_flowers",3},
							"return_to_ready_position")
						return self:promise_sequence(
							{"conjure_flowers",3},
							25,
							{"conjure_flowers",3},
							"return_to_ready_position")
					end)
					:and_then(function()
						boss_reflection:promise_sequence(
							"shoot_lasers",
							"return_to_ready_position")
						return self:promise_sequence(
							{"throw_cards",nil,rnd_int(1,5)},
							"return_to_ready_position",
							100)
					end)
					:and_then(function()
						boss_reflection:promise_sequence(
							{"throw_coins",3},
							"return_to_ready_position")
						return self:promise_sequence(
							{"throw_coins",3},
							"return_to_ready_position",
							100)
					end)
			end
			return promise
				:and_then(function()
					-- called this way so that the progressive decide_next_action
					--   calls don't result in an out of memory exception
					self:decide_next_action()
				end)
		end,
		phase_change=function(self)
			boss_health.phase+=1
			boss_health.health=0
			if boss_health.phase==2 then
				return self:promise_sequence(
					{"return_to_ready_position",2},
					30,
					{"set_all_idle",false},
					10,
					{"pound",0},
					{"pound",0},
					{"pound",3},
					"conjure_bouquet",
					"return_to_ready_position",
					spawn_magic_tile)
			elseif boss_health.phase==3 then
				return self:promise_sequence(
					{"return_to_ready_position",2},
					"cast_reflection",
					"return_to_ready_position",
					spawn_magic_tile,
					60)
			elseif boss_health.phase==4 then
				return self:promise_sequence(
					{"return_to_ready_position",2},
					{"cast_reflection",true},
					function()
						boss_reflection:promise("return_to_ready_position",1,"right")
					end,
					spawn_magic_tile,
					{"return_to_ready_position",1,"left"})
			else
				spawn_magic_tile(140)
				return self:promise(10)
			end
		end,
		cancel_everything=function(self)
			self.left_hand:cancel_everything()
			self.right_hand:cancel_everything()
			self:cancel_promises()
			self:cancel_move()
			self.laser_charge_frames=0
			self.laser_preview_frames=0
			foreach(entities,function(entity)
				if entity.is_boss_generated then
					entity:despawn()
				end
			end)
			foreach(new_entities,function(entity)
				if entity.is_boss_generated then
					entity:despawn()
				end
			end)
		end,
		-- medium-level commands
		pound=function(self,offset)
			return self:promise_parallel(
				{self.left_hand,"pound",offset},
				{self.right_hand,"pound",-offset})
		end,
		reel=function(self)
			local promise=self:promise_sequence(
				{"set_expression",8},
				{"set_all_idle",false})
				:and_then_parallel(
					self.left_hand:promise_sequence({"set_pose",3},"appear"),
					self.right_hand:promise_sequence({"set_pose",3},"appear")
				)
			local i
			for i=1,8 do
				promise=promise:and_then_sequence(
					function()
						freeze_and_shake_screen(0,3)
						self:poof(rnd_int(-15,15),rnd_int(-15,15))
						self.left_hand:move(rnd_int(-8,8),rnd_int(-8,8),6,ease_out,nil,true)
						self.right_hand:move(rnd_int(-8,8),rnd_int(-8,8),6,ease_out,nil,true)
					end,
					{"move",rnd_int(-8,8),rnd_int(-5,2),6,ease_out,nil,true})
			end
			return promise:and_then_sequence(
				10,
				{"set_expression",5},
				20)
		end,
		conjure_bouquet=function(self)
			-- spawn_entity("bouquet",self.left_hand.x,self.left_hand.y)
			self.left_hand.is_holding_bouquet=true
			spawn_petals(self.left_hand.x,self.left_hand.y-6,4,8)
			local promise=self:promise_sequence(
				{"set_expression",1},
				{self.right_hand,"set_pose",3},
				{"move",20,-10,10,ease_in,{0,-5,-5,0},true},
				35,
				{self.left_hand,"move",self.x-2,self.y+11,20,ease_in},
				{self,"set_expression",3},
				30,
				{self,"set_expression",1},
				15)
			promise:and_then_sequence(
				10,
				function()
					self.left_hand.is_holding_bouquet=false
					self.left_hand:set_pose(3)
					self.left_hand:move(-18,6,20,ease_in,nil,true)
				end)
			return promise:and_then_sequence(
				{self.right_hand,"move",0,10,20,ease_in_out,{-25,-20,-25,0},true},
				15)
		end,
		conjure_flowers=function(self,density)
			-- generate a list of flower locations
			local flowers,i,safe_tile={},rnd_int(0,density),rnd_int(0,39)
			while i<40 do
				if i!=safe_tile and i!=safe_tile+7-safe_tile%8*2 then
					add(flowers,{i%8*10+5,8*flr(i/8)+4})
				end
				i+=rnd_int(1,density)
			end
			-- concentrate
			local promise=self:promise_sequence(
				{self.left_hand,"set_idle",false},
				{self.right_hand,"set_idle",false},
				{self,"set_idle",false})
				:and_then_parallel(
					{self.left_hand,"move_to_temple",self},
					{self.right_hand,"move_to_temple",self})
				:and_then("set_expression",2)
			-- spawn the flowers
			self.flowers={}
			local promise2=promise
			for i=1,#flowers do
				-- shuffle flowers
				local j=rnd_int(i,#flowers)
				flowers[i],flowers[j]=flowers[j],flowers[i]
				promise2=promise2:and_then("spawn_flower",flowers[i][1],flowers[i][2])
			end
			-- bloom the flowers
			return promise:and_then_sequence(56,"bloom_flowers",30)
		end,
		cast_reflection=function(self,upgraded_version)
			local promise=self:promise("summon_wands",upgraded_version)
				:and_then(30)
			if upgraded_version then
				promise:and_then(self.right_hand,"cast_spell")
			end
			return promise:and_then(self.left_hand,"cast_spell")
				:and_then(self,"set_expression",3)
				:and_then(5)
				:and_then(function()
					if upgraded_version then
						boss_reflection=spawn_entity("magic_mirror_reflection")
						self.home_x+=20
					else
						player_reflection=spawn_entity("player_reflection")
					end
				end)
				:and_then(55)
		end,
		summon_wands=function(self,right_hand_too)
			local promise=self:promise("set_all_idle",false)
				:and_then("set_expression",2)
				:and_then(self.left_hand,"move",23,14,20,ease_in,nil,true)
				:and_then("set_pose",1)
			local i
			for i=1,2 do
				promise=promise
					:and_then(self.right_hand,"move",-10,0,20,linear,{0,-3,0,-3},true)
					:and_then("move",10,0,20,linear,{0,3,0,3},true)
			end
			if right_hand_too then
				promise
					:and_then(self.right_hand,"set_pose",1)
					:and_then("summon_wand")
			end
			return promise
				:and_then(self,"set_expression",1)
				:and_then(self.left_hand,"summon_wand")
				:and_then(self)
		end,
		throw_cards=function(self,hand,heart_row)
			local promises={}
			if hand!="right" then
				add(promises,{self.left_hand,"throw_cards",heart_row})
			end
			if hand!="left" then
				add(promises,{self.right_hand,"throw_cards",heart_row})
			end
			return self:promise_parallel(unpack(promises))
		end,
		throw_coins=function(self,num_coins,heart_index)
			local promise=self:promise(self.right_hand,"move_to_temple",self)
			local i
			for i=1,num_coins do
				promise=promise:and_then_sequence(
					{self.right_hand,"set_pose",1},
					{"set_idle",false},
					{self,"set_expression",7},
					{"set_idle",false},
					ternary(i==1,24,3),
					{"spawn_coin",i==heart_index},
					3,
					{self.right_hand,"set_pose",4},
					{self,"set_expression",3},
					20)
			end
			return promise
		end,
		shoot_lasers=function(self)
			self.left_hand:disapper()
			local promise=self:promise_sequence(
				{"set_held_state","right"},
				{"set_expression",5},
				{"set_all_idle",false})
			local i
			local col=rnd_int(0,7)
			for i=1,3 do
				col=(col+rnd_int(2,6))%8
				promise=promise:and_then_sequence(
					{"move",10*col+5,-20,15,ease_in,{0,-10,0,-10}},
					"fire_laser")
			end
			return promise
		end,
		-- lowest-level commands
		bloom_flowers=function(self)
			local i
			for i=1,#self.flowers do
				self.flowers[i]:bloom()
			end
			return self:promise_sequence(
				{self.left_hand,"set_pose",5},
				{self.right_hand,"set_pose",5},
				{self,"set_expression",3})
		end,
		return_to_ready_position=function(self,expression,held_hand)
			self.left_hand.holding_wand=false
			self.right_hand.holding_wand=false
			return self:promise_sequence(
				{"set_idle",true},
				{"set_expression",expression or 1},
				{self.left_hand,"set_pose",3},
				{"set_idle",true},
				{self.right_hand,"set_pose",3},
				{"set_idle",true},
				{self,"move_to_home",held_hand})
				:and_then(function()
					if not self.left_hand.visible then
						self.left_hand:appear()
					end
					if not self.right_hand.visible then
						self.right_hand:appear()
					end
				end)
				:and_then("set_held_state",held_hand)
		end,
		move_to_home=function(self,held_hand)
			local promise=self:promise()
			local dx,dy=self.home_x-self.x,self.home_y-self.y
			if abs(dx)>10 or abs(dy)>10 then
				promise=promise:and_then("set_held_state",held_hand or "either")
			end
			return promise:and_then(function()
					local promises={}
					if self.x!=self.home_x or self.y!=self.home_y then
						add(promises,{self,"move",self.home_x,self.home_y,30,ease_in})
					end
					if not self.left_hand.is_holding_mirror and self.left_hand.x!=22 and self.left_hand!=-23 then
						add(promises,{self.left_hand,"move",self.home_x-18,self.home_y+5,30,ease_in,{-10,-10,-20,0}})
					end
					if not self.right_hand.is_holding_mirror and self.right_hand.x!=58 and self.right_hand!=-23 then
						add(promises,{self.right_hand,"move",self.home_x+18,self.home_y+5,30,ease_in,{10,-10,20,0}})
					end
					return self:promise_parallel(unpack(promises))
				end)
		end,
		set_held_state=function(self,held_hand)
			local promises={}
			local lh,rh=self.left_hand,self.right_hand
			if held_hand=="either" then
				if rh.is_holding_mirror then
					held_hand="right"
				else
					held_hand="left"
				end
			end
			if lh.is_holding_mirror and held_hand!="left" then
				add(promises,{lh,"release_mirror"})
			elseif not lh.is_holding_mirror and held_hand=="left" then
				add(promises,{lh,"grab_mirror_handle"})
			end
			if rh.is_holding_mirror and held_hand!="right" then
				add(promises,{rh,"release_mirror"})
			elseif not rh.is_holding_mirror and held_hand=="right" then
				add(promises,{rh,"grab_mirror_handle"})
			end
			if #promises>0 then
				return self:promise_parallel(unpack(promises))
			end
		end,
		fire_laser=function(self)
			return self:promise_sequence(
				{"charge_laser",10},
				4,
				{"preview_laser",6},
				{"set_expression",0},
				{"spawn_laser",14},
				{"set_expression",5},
				{"preview_laser",4})
		end,
		charge_laser=function(self,frames)
			self.laser_charge_frames=frames
			return frames
		end,
		spawn_laser=function(self,frames)
			freeze_and_shake_screen(0,4)
			spawn_entity("mirror_laser",self.x,self.y,{frames_to_death=frames})
			return frames
		end,
		preview_laser=function(self,frames)
			self.laser_preview_frames=frames
			return frames
		end,
		despawn_coins=function(self)
			local i
			for i=1,#self.coins do
				self.coins[i]:die()
			end
			self.coins={}
			return 10
		end,
		set_idle=function(self,idle)
			self.is_idle=idle
		end,
		set_all_idle=function(self,idle)
			self:set_idle(idle)
			self.left_hand:set_idle(idle)
			self.right_hand:set_idle(idle)
		end,
		spawn_flower=function(self,x,y)
			add(self.flowers,spawn_entity("flower_patch",x,y))
			return 1
		end,
		spawn_coin=function(self,has_heart)
			add(self.coins,spawn_entity("coin",self.x+12,self.y,{has_heart=has_heart}))
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
	magic_mirror_reflection={
		render_layer=5,
		extends="magic_mirror",
		visible=true,
		expression=1,
		is_wearing_top_hat=true,
		home_x=20,
		is_reflection=true,
		init=function(self)
			self:super_init()
			self.left_hand.visible=true
			self.left_hand.pose=boss.left_hand.pose
			self.left_hand.x=boss.left_hand.x
			self.left_hand.y=boss.left_hand.y
			self.right_hand.visible=true
			self.right_hand.pose=boss.right_hand.pose
			self.right_hand.x=boss.right_hand.x
			self.right_hand.y=boss.right_hand.y
		end
	},
	magic_mirror_hand={
		-- is_right_hand,dir
		extends="movable",
		-- is_holding_bouquet=false,
		render_layer=8,
		pose=3,
		dir=-1,
		idle_mult=0,
		idle_x=0,
		idle_y=0,
		update=function(self)
			if self.is_reflection then
				self.render_layer=6
			end
			if self.is_idle then
				self.idle_mult=min(self.idle_mult+0.05,1)
			else
				self.idle_mult=max(0,self.idle_mult-0.05)
			end
			local f=boss.frames_alive+ternary(self.is_right_hand,9,4)
			self.idle_x=self.idle_mult*3*sin(f/60)
			self.idle_y=self.idle_mult*4*sin(f/30)
			self:apply_move()
			self:apply_velocity()
			if self.is_holding_mirror then
				self.idle_x=self.mirror.idle_x
				self.idle_y=self.mirror.idle_y
				self.x=self.mirror.x+2*self.dir
				self.y=self.mirror.y+13
			end
		end,
		draw=function(self)
			local x,y=self.x+self.idle_x,self.y+self.idle_y
			if self.visible then
				if self.is_holding_bouquet then
					pal2(4)
					sspr2(97,85,9,16,self.x-1,self.y-12)
					pal()
				end
				if self.is_reflection then
					local i
					for i=1,15 do
						pal2(i,3)
					end
					pal2(7,11)
					pal2(6,11)
				elseif boss_health.rainbow_frames>0 then
					local i
					for i=1,15 do
						pal2(i,16)
					end
					pal2(13,16,-1)
				end
				pal2(3)
				sspr2(12*self.pose-12,51,12,11,x-ternary(self.is_right_hand,7,4),y-8,self.is_right_hand)
				if self.holding_wand then
					if self.pose==1 then
						sspr2(64,30,7,13,x+ternary(self.is_right_hand,-10,4),y-8,self.is_right_hand)
					else
						sspr2(71,30,7,13,x-ternary(self.is_right_hand,3,2),y-16,self.is_right_hand)
					end
				end
			end
		end,
		-- highest-level commands
		throw_cards=function(self,heart_row)
			local promise=self:promise(8-self.dir*8)
				:and_then("set_idle",false)
			local i
			for i=ternary(self.is_right_hand,1,2),5,2 do
				promise=promise:and_then("throw_card_at_row",i,i==heart_row)
			end
			return promise
		end,
		cast_spell=function(self)
			return self:promise("move",40+20*self.dir,-30,12,ease_out,{-20,20,0,20},false)
				:and_then("set_pose",6)
				:and_then(function()
					spawn_particle_burst(self.x,self.y-20,20,3,10)
					freeze_and_shake_screen(0,20)
				end)
		end,
		throw_card_at_row=function(self,row,has_heart)
			return self:promise("move_to_row",row):and_then(6)
				:and_then("set_pose",1):and_then("spawn_card",has_heart):and_then(6)
				:and_then("set_pose",2):and_then(3)
		end,
		spawn_card=function(self,has_heart)
			spawn_entity("playing_card",self.x-10*self.dir,self.y,{vx=-1.5*self.dir,has_heart=has_heart})
		end,
		grab_mirror_handle=function(self)
			return self:promise_sequence(
				{"set_pose",3},
				{"move",self.mirror.x+2*self.dir,self.mirror.y+13,10,ease_out,{10*self.dir,5,0,20}},
				{"set_pose",2},
				function()
					self.is_holding_mirror=true
				end)
		end,
		cancel_everything=function(self)
			self:cancel_promises()
			self.holding_wand=false
			self.is_holding_mirror=false
			self:cancel_move()
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
		summon_wand=function(self)
			self.holding_wand=true
			return self:promise("poof",-10*self.dir)
		end,
		set_idle=function(self,idle)
			self.is_idle=idle
		end,
		release_mirror=function(self)
			self.is_holding_mirror=false
			return self:promise_sequence(
				{"set_pose",3},
				{"move",15*self.dir,-7,25,ease_in,nil,true})
		end,
		appear=function(self)
			self.visible=true
			return self:poof()
		end,
		disapper=function(self)
			self.visible=false
			return self:poof()
		end,
		pound=function(self,offset)
			return self:promise_sequence(
				{"set_pose",2},
				{"move",self.mirror.x+20*self.dir,self.mirror.y+20,10,ease_in}, -- move out
				{"move",self.mirror.x+ternary(offset==0,4,0)*self.dir,self.mirror.y+20+offset,5,ease_out}, -- move in
				function()
					freeze_and_shake_screen(0,2)
				end,
				1)
		end,
		move_to_temple=function(self,mirror)
			return self:promise("set_pose",1)
				:and_then("move",mirror.x+13*self.dir,mirror.y,20)
		end,
		move_to_row=function(self,row)
			return self:promise("set_pose",3)
				:and_then("move",40+50*self.dir,8*row-4,18,ease_in_out,{10*self.dir,-10,10*self.dir,10})
				:and_then("set_pose",2)
		end,
		set_pose=function(self,pose)
			if not self.is_holding_mirror then
				self.pose=pose
			end
		end,
		poof=function(self,dx,dy)
			spawn_entity("poof",self.x+(dx or 0),self.y+(dy or 0))
			return 12
		end
	},
	mirror_laser={
		hitbox_channel=1, -- player
		is_boss_generated=true,
		render_layer=9,
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
				sspr2(ternary(f%30<20,36,45),30,9,7,self.x-4,self.y-5-max(0,self.frames_alive-0.09*self.frames_alive*self.frames_alive))
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
	calc_rainbow_color()
	scene[1]()
end

local skip_frames=0
function _update()
	skip_frames=increment_counter(skip_frames)
	if skip_frames%1>0 then return end
	if freeze_frames>0 then
		freeze_frames=decrement_counter(freeze_frames)
		player:check_inputs() -- todo other scenes won't like this
	else
		screen_shake_frames,scene_frame=decrement_counter(screen_shake_frames),increment_counter(scene_frame)
		calc_rainbow_color()
		-- update promises
		local num_promises,i=#promises
		for i=1,num_promises do
			promises[i]:update()
		end
		filter_out_finished(promises)
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
	-- print("mem:      "..flr(100*(stat(0)/1024)).."%",2,102,ternary(stat(1)>=1024,8,3))
	-- print("cpu:      "..flr(100*stat(1)).."%",2,109,ternary(stat(1)>=1,8,3))
	-- print("entities: "..#entities,2,116,ternary(#entities>50,8,3))
	-- print("promises: "..#promises,2,123,ternary(#promises>30,8,3))
end


-- game functions
function init_game()
	-- reset everything
	entities,new_entities={},{}
	-- create starting entities
	tiles_collected=0
	player=spawn_entity("player",35,20)
	player_health=spawn_entity("player_health")
	player_reflection=nil
	boss=nil
	boss_reflection=nil
	boss_health=spawn_entity("boss_health")
	if beginning_phase>0 then
		boss=spawn_entity("magic_mirror")
		boss.visible=true
		-- player_health.visible=true
		boss_health.visible=true
		boss_health.phase=beginning_phase-1
		if beginning_phase>3 then
			player_reflection=spawn_entity("player_reflection")
		end
		boss:promise_sequence(
			"skip_to_fight",
			"phase_change",
			"return_to_ready_position",
			"decide_next_action")
	else
		-- start the slow intro to the game
		spawn_entity("instructions")
	end
	-- immediately add new entities to the game
	add_new_entities()
end

function update_game()
	-- sort entities for updating
	sort_list(entities,updates_before)
	-- update entities
	local entity
	for entity in all(entities) do
		-- call the entity's update function
		entity:update()
		-- do some default update stuff
		decrement_counter_prop(entity,"invincibility_frames")
		entity.frames_alive=increment_counter(entity.frames_alive)
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
	filter_out_finished(entities)
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
	-- debug phase number
	print(boss_health.phase,98,3,1)
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
			-- finished=false,
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
				self.finished=true
			end,
			despawn=function(self)
				self.finished=true
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
			promise=function(self,...)
				return make_promise(self):start():and_then(...)
			end,
			promise_sequence=function(self,...)
				return make_promise(self):start():and_then_sequence(...)
			end,
			promise_parallel=function(self,...)
				return make_promise(self):start():and_then_parallel(...)
			end,
			cancel_promises=function(self)
				foreach(promises,function(promise)
					if promise.ctx==self then
						promise:cancel()
					end
				end)
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
	entity.class_name=class_name
	-- add properties onto it from the arguments
	for k,v in pairs(args or {}) do
		entity[k]=v
	end
	if not skip_init then
		-- initialize it
		entity:init()
		-- add it to the list of entities-to-be-added
		add(new_entities,entity)
	end
	-- return it
	return entity
end

function add_new_entities()
	foreach(new_entities,function(entity)
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

-- promise functions
function make_promise(ctx,fn,...)
	local args={...}
	return {
		ctx=ctx,
		and_thens={},
		frames_to_finish=0,
		start=function(self)
			if not self.started and not self.canceled then
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
			return self
		end,
		update=function(self)
			if decrement_counter_prop(self,"frames_to_finish") then
				self:finish()
			end
		end,
		finish=function(self)
			if not self.finished and not self.canceled then
				self.finished=true
				foreach(self.and_thens,function(promise)
					promise:start()
				end)
			end
		end,
		cancel=function(self)
			if not self.canceled then
				self.canceled,self.finished=true,true
				if self.parent_promise then
					self.parent_promise:cancel()
				end
				foreach(self.and_thens,function(promise)
					promise:cancel()
				end)
			end
		end,
		and_then=function(self,ctx,...)
			local promise
			if type(ctx)=="table" then
				promise=make_promise(ctx,...)
			else
				promise=make_promise(self.ctx,ctx,...)
			end
			promise.parent_promise=self
			-- start the promise now, or schedule it to start when this promise finishes
			if self.canceled then
				promise:cancel()
			elseif self.finished then
				promise:start()
			else
				add(self.and_thens,promise)
			end
			return promise
		end,
		and_then_sequence=function(self,args,...)
			local promises={...}
			local promise
			if type(args)=="table" then
				promise=self:and_then(unpack(args))
			else
				promise=self:and_then(args)
			end
			if #promises>0 then
				return promise:and_then_sequence(unpack(promises))
			end
			return promise
		end,
		and_then_parallel=function(self,...)
			local overall_promise,promises,num_finished=make_promise(self.ctx),{...},0
			if #promises==0 then
				overall_promise:finish()
			else
				local parallel_promise
				foreach(promises,function(parallel_promise)
					local temp_promise
					if type(parallel_promise)=="table" then
						temp_promise=self:and_then(unpack(parallel_promise))
					else
						temp_promise=self:and_then(parallel_promise)
					end
					temp_promise:and_then(function()
						num_finished+=1
						if num_finished==#promises then
							overall_promise:finish()
						end
					end)
				end)
			end
			return overall_promise
		end
	}
end

-- magic tile functions
function on_magic_tile_picked_up(tile)
	if boss_health.health<60 then
		spawn_magic_tile(ternary(boss_health.phase<1,80,120)-min(tile.frames_alive,30)) -- 30 frame grace period
	end
	tiles_collected=increment_counter(tiles_collected)
	if boss_health.phase==0 then
		if tiles_collected==2 then
			boss_health.visible=true
		elseif tiles_collected==4 then
			boss=spawn_entity("magic_mirror")
		elseif tiles_collected==5 then
			boss.visible=true
		elseif tiles_collected==6 then
			boss:promise_sequence(
				"intro",
				"phase_change",
				{"return_to_ready_position",nil,"right"},
				"decide_next_action")
		end
	elseif boss_health.phase>0 then
		if boss_health.health>=60 then
			boss:cancel_everything()
			boss:promise_sequence(
				"reel",
				"phase_change",
				{"return_to_ready_position",2},
				{boss,"decide_next_action"})
		end
	end
end

function spawn_magic_tile(frames_to_death)
	spawn_entity("magic_tile_spawn",10*rnd_int(1,8)-5,8*rnd_int(1,5)-4,{frames_to_death=max(10,frames_to_death or 0)})
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

function spawn_petals(x,y,num_petals,color)
	local i
	for i=1,num_petals do
		spawn_entity("particle",x,y-2,{
			vx=(i-num_petals/2),
			vy=rnd_num(-2,-1),
			friction=0.1,
			gravity=0.06,
			frames_to_death=rnd_int(10,17),
			color=color
		})
	end
end

-- drawing functions
function calc_rainbow_color()
	local rainbow_color=8+flr(scene_frame/4)%6
	color_ramps[16]=color_ramps[ternary(rainbow_color==13,14,rainbow_color)]
end

function get_color(c,fade) -- fade between 3 (lightest) and -3 (darkest)
	return color_ramps[c or 0][4-(fade or 0)]
end

function pal2(c1,c2,fade)
	local c3=get_color(c2,fade or 0)
	pal(c1,c3)
	palt(c1,c3==0)
end

function sspr2(x,y,width,height,x2,y2,flip_horizontal,flip_vertical)
	sspr(x,y,width,height,x2+0.5,y2+0.5,width,height,flip_horizontal,flip_vertical)
end

-- tile functions
function is_tile_occupied(col,row)
	local e
	for e in all(entities) do
		if e.occupies_tile and e:col()==col and e:row()==row then
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

function ease_out_in(percent)
	return ternary(percent<0.5,ease_in(2*percent)/2,0.5+ease_out(2*percent-1)/2)
end

-- helper functions
function freeze_and_shake_screen(f,s)
	freeze_frames=max(f,freeze_frames)
	screen_shake_frames=max(s,screen_shake_frames)
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

-- increment a counter, wrapping to 20000 if it risks overflowing
function increment_counter(n)
	if n>32000 then
		return n-12000
	end
	return n+1
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

-- filter out anything in list with finished=true
function filter_out_finished(list)
	local num_deleted,k,v=0
	for k,v in pairs(list) do
		if v.finished then
			list[k]=nil
			num_deleted+=1
		else
			list[k-num_deleted],list[k]=v,nil
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
33333333333333333383333333883333333833333333333333333338833333005533333333333300000000000000000000000000000000000000000000000000
30550550330550550338880888330880880330880880330088800388880588305500003306600300000000000000000000000000000000000000000000000000
35005005335005005338888ee8338888ee8338888ee83308888e03888050ee805550003306600300000000000000000000000000000000000000000000000000
35000005335888885338888ee8338888ee8338888ee83308888e03388808ee803550003305500300000000000000000000000000000000000000000000000000
30500050330588850330888880330888880330888880330888880330800088303000003306600300000000000000000000000000000000000000000000000000
30050500330058500330888880330088800330088800330088800330050880303000003305500300000000000000000000000000000000000000000000000000
33335333333335333338338338338338338333338333333338333333335833303055503305500300000000000000000000000000000000000000000000000000
33333333333333333333333333333333333377733333333333333733333333333005503305500300000000000000000000000000000000000000000000000000
30000000000000033000777000000003300077700000000330000000070000033005553305500300000000000000000000000000000000000000000000000000
30000000000000033007777000000003300700007700000330000000000000073000663305500300000000000000000000000000000000000000000000000000
30000000000000033007770077000003300000007700077730700000000000033000555305500300000000000000000000000000000000000000000000000000
30000770777000033000000077007773307700000000077730000000000000033000066305500300000000000000000000000000000000000000000000000000
30000777777700033077000000007777307700000000700330000000000000033333366333333300000000000000000000000000000000000000000000000000
30007777777700033077700000770777300000000077000330000000000700030000000000000000000000000000000000000000000000000000000000000000
30007777777700033077700777700003300070007777000330000000000000030000000000000000000000000000000000000000000000000000000000000000
30077777777770033000007777770003300000007777000330000000070000070000000000000000000000000000000000000000000000000000000000000000
30077777777770033000007777770003300000700777007770000000000000030000000000000000000000000000000000000000000000000000000000000000
30077777707770033077000777770773777000000000007730000000000000030000000000000000000000000000000000000000000000000000000000000000
30007777000000037777700000000773777000000000070330000000000000030000000000000000000000000000000000000000000000000000000000000000
30007770000000037777700770000773307070770000000330000000000000030000000000000000000000000000000000000000000000000000000000000000
33333333333333333773333773333333333333333333333333333333333333330000000000000000000000000000000000000000000000000000000000000000
33333333333333333333333333333333333333773333333333333373333337733333333300000000000000000000000000000000000000000000000000000000
30000000000330000000000330007700000330777000000330000770000337700770000300000000000000000000000000000000000000000000000000000000
30000000000330000000000330007700000330077000000330000770000337770770000300000000000000000000000000000000000000000000000000000000
30000000000330000000000337700770000330077700000330000770000330770660000300000000000000000000000000000000000000000000000000000000
30007767777730007770000337770670000330007707700330000770000330767770000300000000000000000000000000000000000000000000000000000000
30d77777777730d77777700330677067007730776677700330777770770330077770000300000000000000000000000000000000000000000000000000000000
30d77dd7600330d77dd7700377066766777737777677000330777677770330076670000300000000000000000000000000000000000000000000000000000000
30d77777777730d77777700377776666776337767677000330767677700330077770000300000000000000000000000000000000000000000000000000000000
30d77dd7777730d77dd770033066666666033067677700033066677600033007776d000300000000000000000000000000000000000000000000000000000000
30d67777700330d67777600330006666dd033006666d0003306676600003300066dd000300000000000000000000000000000000000000000000000000000000
333366663333333366663333333333ddd333333366d33333333dddd333333333ddd3333300000000000000000000000000000000000000000000000000000000
33333333333333333333333333333dddd33333666663333666663300000000000000000000000000000000000000000000000000000000000000000000000000
3000000033000000033000000033dddddd033666d7763366d6d76300000000000000000000000000000000000000000000000000000000000000000000000000
300000003300dd0003660000003dddddddd3666ddd77666d6d7d7600000000000000000000000000000000000000000000000000000000000000000000000000
30660000330dddd003666600003dddddddd3666d6667666d666d7600000000000000000000000000000000000000000000000000000000000000000000000000
30006600330dddd003306666003dddddddd3666ddd666666ddd66600000000000000000000000000000000000000000000000000000000000000000000000000
300000003300dd0003300066663dddddddd3d666d666dd666d666d00000000000000000000000000000000000000000000000000000000000000000000000000
3000000033000000033000006633dddddd03dd66666dddd66666dd00000000000000000000000000000000000000000000000000000000000000000000000000
30000000330000000330000000330dddd0033d5ddddd33d5ddddd300000000000000000000000000000000000000000000000000000000000000000000000000
333333333333333333333333333333333333335d5d533335d5d53300000000000000000000000000000000000000000000000000000000000000000000000000
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
00000000000000000000000000000000000000000000000000000000000000000000111111555555555111100000000004003b0004000000000977777777777f
00000000000000000000000000000000000000000000000000000000000000000000333311111111111333300000000004003b0004000000000977777777777f
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004003300040000000009777777777779
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004003300040000000009777777777779
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004003100040000000009777777777779
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004001300040000000009777777777779
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004001300040000000003977777777793
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004441344440000000003977777777793
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
000000000000000000000000000000000000000033336663333333366633333333666333333337773333333376633333333cbb33333333666333333336663333
0000000000000000000000000000000000000000306666666033066666660330777777703307777776033067667770330accbbee033066666660330777777703
000000000000000000000000000000000000000037777777773377766677733ddd777ddd337777766773367677676733aaccbbee83377777dd7733ddd777ddd3
00000000000000000000000000000000000000003ddd777ddd3377777777733777777777337776677663377676767633aaccbbee833dd77777d7337777777773
00000000000000000000000000000000000000007777777777777dd777dd7777d77777d7777667766666676766766776aaccbbee887777777777777d77777d77
000000000000000000000000000000000000000077d77777d777776d7d67777d7d777d7d766776666677767677677666aaccbbee887d77777d7767ddd777ddd7
00000000000000000000000000000000000000007d7d777d7d7777777777777777777777777666667777677676766776aaccbbee88d7d777d7d7677d77777d77
000000000000000000000000000000000000000077d77777d777d7d777d7d777ddddddd7766666777776767767777676aaccbbee887d77777d77777777777777
00000000000000000000000000000000000000007777777777777d77777d7777ddddddd7766677777667776776767766aaccbbee8877777777777777ddddd777
000000000000000000000000000000000000000077d77777d777777777777777ddddddd776777776677767676767766111ee11cc117777dd7777777ddddddd77
012300000000000000000000000000000000000037ddddddd73377ddddd773377ddddd7733777667777336766676673311ee11cc1337dddd7777337d77777d73
456700000000000000000000000000000000000036777777763377d777d7733667777766337667777773376776767633ddddddddd33677777776336777777763
89a3000000000000000000000000000000000000306677766033077777770330666666603307777777033076776670330ddddddd033066777660330666666603
cdef00000000000000000000000000000000000033336663333333366633333333666333333337773333333376733333333ddd33333333666333333336663333

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
010c00000944000400094250942509440004000942509425094400040009425094250944000400094250942510440004001042510425104400040010425104250e440004000e4250e4250e440004000e4250e425
010c00000944000400094250942509440004000942509425094400040009425094250944000400094250942509440004000942509425094400040009425094250944000400094250942509440004000942509425
010c00002174028740247402873021730287302472028720217202871024710287102172028720247302873021740287402474028730217302873024720287202172028710247102871021720287202473028730
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
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
03 02420144
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344


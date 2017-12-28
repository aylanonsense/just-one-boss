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

todo:
	victory screen with high scores
	keep track of high scores
	sound effects + music
	hard mode
	tweak gameplay
	lots of playtesting
]]

-- useful noop function
function noop() end

-- global config vars
local speed_mode=false
local skip_animations=true
local one_hit_ko=true
local one_hit_death=true
local starting_phase=4

-- global scene vars
local scene_frame
local freeze_frames
local screen_shake_frames
local is_paused

-- global game vars
local boss_phase
local rainbow_color
local dark_rainbow_color
local score
local score_mult

-- global promise vars
local promises={}

-- global entity vars
local entities
local new_entities
local title_screen
local player
local player_health
local player_reflection
local player_figment
local boss
local boss_health
local boss_reflection
local left_curtain
local right_curtain

-- global entities classes
local entity_classes={
	top_hat={
		update=function(self)
			if self.frames_alive%15==0 then
				self:poof()
				spawn_entity("bunny",self.x,self.y,{vx=ternary(rnd()<0.5,1,-1)*(1+rnd(2)),vy=-1-rnd(2)})
			end
		end,
		draw=function(self)
			sspr2(100,9,15,12,self.x-8,self.y-1)
		end
	},
	bunny={
		frames_to_death=100,
		update=function(self)
			self.vy+=0.1
			self:apply_velocity()
		end,
		draw=function(self)
			sspr2(47,71,14,13,self.x-7,self.y-7,self.vx>0)
		end
	},
	curtain={
		is_pause_immune=true,
		render_layer=14,
		is_user_interface=true,
		percent_closed=100,
		anim_frames=0,
		dir=1,
		update=function(self)
			decrement_counter_prop(self,"anim_frames")
			self.percent_closed=100*ease_out_in(self.anim_frames/100)
			if self.anim!="open" then
				self.percent_closed=100-self.percent_closed
			end
		end,
		draw=function(self)
			rectfill(self.x-10*self.dir,0,self.x+self.dir*.62*self.percent_closed,127,0)
			local lines,i={0,94,5,70,11,34,21,20}
			for i=1,#lines,2 do
				local x=self.x+0.5+self.dir*(self.percent_closed/10+(1+self.percent_closed/100)*lines[i])
				line(x,11,x,lines[i+1],2)
			end
		end,
		open=function(self)
			self.anim,self.anim_frames="open",ternary(speed_mode,1,100)
		end,
		close=function(self)
			self.anim,self.anim_frames="close",ternary(speed_mode,1,100)
		end
	},
	title_screen={
		extends="movable",
		x=40,
		y=26,
		is_user_interface=true,
		is_pause_immune=true,
		render_layer=15,
		update=function(self)
			if btnp(1) and not self.is_activated then
				self.is_activated=true
				self.x+=2
				self:move(-127,0,ternary(speed_mode,30,100),ease_in_out,{70,0,0,0},true)
				left_curtain:promise_sequence(ternary(speed_mode,15,27),"open")
				right_curtain:promise_sequence(ternary(speed_mode,15,27),"open")
					:and_then(function()
						entities,new_entities,boss_phase,score,score_mult,is_paused={title_screen,left_curtain,right_curtain},{},max(0,starting_phase-1),0,1 -- ,false
						player,player_health,boss_health=spawn_entity("player"),spawn_entity("player_health"),spawn_entity("boss_health")
						player_reflection,player_figment,boss,boss_reflection=nil -- ,nil,...
						if starting_phase>0 then
							boss=spawn_entity("magic_mirror")
							boss.visible,boss_health.visible=true,true
							boss:promise_sequence(30,"intro")
							if starting_phase>1 then
								boss.is_wearing_top_hat=true
							end
							if starting_phase>3 then
								player_reflection=spawn_entity("player_reflection")
							end
						else
							spawn_magic_tile(ternary(speed_mode,10,210))
						end
					end)
			end
			self:apply_move()
		end,
		draw=function(self)
			sspr2(0,71,47,16,self.x,self.y)
			sspr2(0,88,47,40,self.x,self.y+18)
			if self.frames_alive%30<22 and not self.is_activated then
				print("press    to begin",self.x-10,self.y+73,13)
				sspr2(88,12,8,7,self.x+14,self.y+72)
			end
		end
	},
	death_prompt={
		is_user_interface=true,
		render_layer=17,
		is_pause_immune=true,
		update=function(self)
			if self.frames_alive>120 and btnp(0) then
				self:die()
				local movables,movable={player_figment,player_health,title_screen}
				for movable in all(movables) do
					movable:move(127,0,ternary(speed_mode,30,100),ease_in_out,{-70,0,0,0},true)
					movable.x-=2
				end
				title_screen:promise_sequence(
					ternary(speed_mode,40,110),
					function()
						starting_phase,title_screen.is_activated=1 -- ,false
					end)
			end
		end,
		draw=function(self)
			if self.frames_alive>120 and self.frames_alive%30<22 then
				print("press    to return",29,99,13)
				print("to menu",49,107)
				sspr2(88,12,8,7,52,98,true)
			end
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
			self:apply_velocity()
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
	player_figment={
		is_pause_immune=true,
		extends="movable",
		is_user_interface=true,
		render_layer=17,
		update=function(self)
			self:apply_move()
		end,
		draw=function(self)
			if self.frames_alive<120 then
				sspr2(88,4,9,8,self.x-4,self.y-6)
			else
				sspr2(88,0,13,4,self.x-6,self.y-4)
			end
		end
	},
	player={
		hitbox_channel=2, -- pickup
		hurtbox_channel=1, -- player
		facing=1, -- 0 = left, 1 = right, 2 = up, 3 = down
		step_frames=0,
		teeter_frames=0,
		bump_frames=0,
		stun_frames=0,
		primary_color=12,
		secondary_color=13,
		tertiary_color=0,
		x=35,
		y=20,
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
					local occupant=get_tile_occupant(col,row)
					if occupant or (player_reflection and (self.prev_col<5)!=(col<5)) then
						self:bump()
						if occupant then
							occupant:get_bumped()
						end
					end
				end
			end
		end,
		draw=function(self)
			if self.invincibility_frames%4<2 or self.stun_frames>0 then
				local sx,sy,sh,dx,dy,facing,flipped=0,0,8,3+4*self.facing,6,self.facing,self.facing==0
				-- up/down sprites are below the left/right sprites in the spritesheet
				if facing==2 then
					sy,sh,dx=8,11,5
				elseif facing==3 then
					sy,sh,dx,dy=19,11,5,9
				end
				-- moving between tiles
				if self.step_frames>0 then
					sx=44-11*self.step_frames
				end
				-- teetering off the edge or bumping into a wall
				if self.teeter_frames>0 or self.bump_frames>0 then
					sx=66
					if self.bump_frames<=0 then
						local c=ternary(self.teeter_frames%4<2,8,9)
						palt(c,true)
						pal(17-c,self.secondary_color)
						sx=44
					end
					if facing>1 then
						dy+=13-5*facing
					else
						dx+=4-facing*8
					end
					if self.teeter_frames<3 and self.bump_frames<3 then
						sx=55
					end
				end
				-- getting hurt
				if self.stun_frames>0 then
					sx,sy,sh,dx,dy,flipped=77,0,10,5,8,self.stun_frames%6>2
				end
				-- draw the sprite
				pal(12,self.primary_color)
				pal(13,self.secondary_color)
				pal(1,self.tertiary_color)
				sspr2(sx,sy,11,sh,self.x-dx,self.y-dy,flipped)
			end
		end,
		check_inputs=function(self)
			local i
			for i=0,3 do
				if btnp(i) then
					self:queue_step(i)
					break
				end
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
				if dir>1 then
					self.vy+=(2*dir-5)*ternary(dist>2,dist-1,dist)
				else
					self.vx+=2*dir*dist-dist
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
			spawn_entity("pain",self.x,self.y)
			self:get_hurt()
		end,
		get_hurt=function(self)
			if self.invincibility_frames<=0 then
				score_mult=1
				freeze_and_shake_screen(6,10)
				self.invincibility_frames,self.stun_frames=60,19
				player_health:lose_heart()
			end
		end
	},
	player_health={
		extends="movable",
		is_pause_immune=true,
		x=63,
		y=122,
		hearts=4,
		-- anim=nil,
		anim_frames=0,
		is_user_interface=true,
		update=function(self)
			if decrement_counter_prop(self,"anim_frames") then
				self.anim=nil
			end
			self:apply_move()
		end,
		draw=function(self)
			if self.visible then
				local i
				for i=1,4 do
					sspr2(0,30,9,7,self.x+8*i-24,self.y-3)
					local sprite=0
					if self.anim=="gain" and i==self.hearts then
						sprite=mid(1,5-flr(self.anim_frames/2),3)
					elseif self.anim=="lose" and i==self.hearts+1 then
						sprite=6
					elseif i<=self.hearts then
						sprite=4
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
			if one_hit_death then
				self.hearts=0
			end
			if self.hearts>0 then
				self.hearts-=1
				self.anim,self.anim_frames="lose",20
			end
			if self.hearts<=0 then
				promises,is_paused,player_health.render_layer={},true,16
				freeze_and_shake_screen(35,0)
				spawn_entity("death_prompt")
				player_figment=spawn_entity("player_figment",player.x+23,player.y+65)
				player_figment:promise("move",63,72,60,linear)
				left_curtain:close()
				right_curtain:close()
				player_health:promise_sequence(
					30,
					{"move",63,45,60,ease_in_out,{-60,10,-40,10}})
				player:die()
				player=nil
			end
		end
	},
	boss_health={
		-- x=63,
		-- y=5,
		-- visible=false,
		health=0,
		rainbow_frames=0,
		is_user_interface=true,
		drain_frames=0,
		update=function(self)
			decrement_counter_prop(self,"rainbow_frames")
			if self.drain_frames>0 then
				self.health-=1
			end
			decrement_counter_prop(self,"drain_frames")
		end,
		draw=function(self)
			if self.visible then
				rect(33,2,93,8,ternary(self.rainbow_frames>0,rainbow_color,5))
				rectfill(33,2,mid(33,32+self.health,92),8)
			end
		end,
		gain_health=function(self)
			if self.health<60 then
				self.health,self.visible,self.rainbow_frames=mid(0,self.health+1,60),true,15
				local health=self.health
				if boss_phase==0 then
					if health==25 then
						boss=spawn_entity("magic_mirror")
					elseif health==37 then
						boss.visible=true
					elseif health==60 then
						boss:intro()
					end
				elseif health>=60 then
					if boss_phase>=5 then
						self.health=0
					elseif boss_phase==4 then
						boss_phase=5
						boss:promise_sequence(
							"cancel_everything",
							{"reel",60},
							"cancel_everything",
							{"move",40,-20,15,ease_in},
							20,
							function()
								player_reflection:poof()
								player_reflection=player_reflection:die() -- nil
								spawn_entity("top_hat",40,-20):poof()
							end,
							"die",
							120,
							function()
								left_curtain:close()
								right_curtain:close()
							end,
							100,
							function()
								is_paused=true
							end)
						boss_reflection:promise_sequence(
							"cancel_everything",
							{"reel",57},
							"die")
						local i
						for i=1,18 do
							spawn_magic_tile(20+13*i)
						end
					else
						boss:promise_sequence(
							"cancel_everything",
							{"reel",8},
							10,
							"set_expression",
							20,
							"phase_change",
							spawn_magic_tile,
							function()
								boss_phase+=1
							end,
							{"return_to_ready_position",2},
							"decide_next_action")
					end
				end
			end
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
		is_boss_generated=true,
		update=function(self)
			if get_tile_occupant(self:col(),self:row()) then
				self:die()
				spawn_magic_tile(10)
			end
		end,
		draw=function(self)
			local x,y,tile_color,bg_color=self.x,self.y,rainbow_color,1
			if self.frames_to_death>0 or self.frames_alive<4 then
				tile_color,bg_color=7,7
				if self.frames_to_death==mid(1,self.frames_to_death,2) then
					tile_color,bg_color=6,6
				end
			end
			pal(7,tile_color)
			pal(5,bg_color)
			sspr2(55,38,9,7,x-4,y-3)
		end,
		on_hurt=function(self)
			score+=score_mult
			spawn_entity("points",self.x,self.y-7,{points=score_mult})
			freeze_and_shake_screen(2,2)
			self.hurtbox_channel,self.frames_to_death,score_mult=0,6,min(score_mult+1,8)
			local health_change=ternary(one_hit_ko and boss_phase<5,60,ternary(boss_phase==0,12,8))
			local particles,i=spawn_particle_burst(self.x,self.y,max(health_change,ternary(boss_phase>=5,15,30)),16,10)
			for i=1,health_change do
				-- shuffle
				local j=rnd_int(i,#particles)
				particles[i],particles[j]=particles[j],particles[i]
				-- move towards and fill the boss bar
				particles[i].frames_to_death,particles[i].on_death=15+ternary(speed_mode,0,i),function()
					boss_health:gain_health()
				end
				particles[i]:promise_sequence(
					7+ternary(speed_mode,0,i),
					{"move",8+min(boss_health.health+i,60),-58,8,ease_out})
			end
			on_magic_tile_picked_up(self,health_change)
		end
	},
	player_reflection={
		extends="player",
		update_priority=10,
		primary_color=11,
		secondary_color=3,
		tertiary_color=3,
		init=function(self)
			self:copy_player()
			spawn_entity("poof",self.x,self.y)
		end,
		update=function(self)
			local prev_col,prev_row=self:col(),self:row()
			self:copy_player()
			local occupant=get_tile_occupant(self:col(),self:row())
			if (prev_col!=self:col() or prev_row!=self:row()) and occupant  and player then
				player:bump()
				self:copy_player()
				occupant:get_bumped()
			end
		end,
		on_hurt=function(self,entity)
			if player then
				player:get_hurt(entity)
				self:copy_player()
				spawn_entity("pain",self.x,self.y)
			end
		end,
		copy_player=function(self)
			if player then
				-- 0 = left, 1 = right, 2 = up, 3 = down
				local mirrored_directions={1,0,2,3}
				self.x,self.y,self.facing=80-player.x,player.y,mirrored_directions[player.facing+1]
				self.step_frames,self.stun_frames,self.teeter_frames=player.step_frames,player.stun_frames,player.teeter_frames
				self.bump_frames,self.invincibility_frames,self.frames_alive=player.bump_frames,player.invincibility_frames,player.frames_alive
			end
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
			-- some cards are red
			if self.has_heart then
				pal(5,8)
				pal(6,15)
			end
			-- spin counter-clockwise when moving left
			local f=flr(self.frames_alive/5)%4
			if self.vx<0 then
				f=(6-f)%4
			end
			-- draw the card
			sspr2(10*f+77,21,10,10,self.x-5,self.y-7)
		end
	},
	flower_patch={
		render_layer=4,
		is_boss_generated=true,
		hit_frames=0,
		update=function(self)
			if decrement_counter_prop(self,"hit_frames") then
				self.hitbox_channel=0
			end
		end,
		draw=function(self)
			local sx=101
			if self.hit_frames>0 then
				sx=119
			elseif self.frames_to_death>0 then
				sx=110
			end
			sspr2(sx,71,9,8,self.x-4,self.y-4)
		end,
		bloom=function(self)
			self.frames_to_death,self.hit_frames,self.hitbox_channel=ternary(boss_phase==4,10,30),3,1
			spawn_petals(self.x,self.y,2,8)
		end
	},
	coin={
		extends="movable",
		is_boss_generated=true,
		health=3,
		init=function(self)
			self.target_x,self.target_y=10*self.target:col()-5,8*self.target:row()-4
			self:promise_sequence(
				{"move",self.target_x+2,self.target_y,30,ease_out,{20,-30,10,-60}},
				2,
				function()
					self.hitbox_channel=5 -- player, coin
					self.occupies_tile=true
					freeze_and_shake_screen(2,2)
				end,
				{"move",-1,-4,3,ease_in,nil,true},
				2,
				{"move",-1,4,3,ease_out,nil,true},
				function()
					self.hitbox_channel=1 -- player
					self.hurtbox_channel=4 -- coin
				end)
		end,
		update=function(self)
			self:apply_move()
		end,
		draw=function(self)
			if self.frames_alive<36 then
				circfill(self.target_x,self.target_y,min(flr(self.frames_alive/7),4),2)
			end
			local sprite=0
			if self.frames_alive>20 then
				sprite=2
			end
			if self.frames_alive>=30 then
				sprite=ternary(self.health<3,5,4)
			else
				sprite+=flr(self.frames_alive/3)%2
			end
			sspr(9*sprite,37,9,9,self.x-4,self.y-5)
		end,
		get_bumped=function(self)
			self.health-=1
			if self.health<=0 then
				self:die()
			end
		end,
		on_death=function(self)
			spawn_particle_burst(self.x,self.y,6,6,4)
			if self.has_heart then
				spawn_entity("heart",self.x,self.y)
			end
		end
	},
	particle={
		render_layer=11,
		extends="movable",
		friction=1,
		gravity=0,
		color=7,
		init=function(self)
			self:update()
		end,
		update=function(self)
			self.vy+=self.gravity
			self.vx*=self.friction
			self.vy*=self.friction
			self.prev_x,self.prev_y=self.x,self.y
			self:apply_move()
		end,
		draw=function(self)
			line(self.x,self.y,self.prev_x,self.prev_y,ternary(self.color==16,rainbow_color,self.color))
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
		-- visible=false,
		init=function(self)
			local props,y={mirror=self,is_reflection=self.is_reflection},self.y+5
			self.left_hand=spawn_entity("magic_mirror_hand",self.x-18,y,props)
			self.coins,self.flowers,props.is_right_hand,props.dir={},{},true,1
			self.right_hand=spawn_entity("magic_mirror_hand",self.x+18,y,props)
		end,
		update=function(self)
			decrement_counter_prop(self,"laser_charge_frames")
			decrement_counter_prop(self,"laser_preview_frames")
			self.idle_mult=ternary(self.is_idle,min(self.idle_mult+0.05,1),max(0,self.idle_mult-0.05))
			self.idle_x,self.idle_y=self.idle_mult*3*sin(self.frames_alive/60),self.idle_mult*2*sin(self.frames_alive/30)
			self:apply_move()
			-- keep mirror in bounds (for reeling purposes)
			self.x,self.y=mid(0,self.x,80),mid(-40,self.y,-20)
			-- create particles when charging laser
			if self.laser_charge_frames>0 then
				local x,y,angle=self.x,self.y,rnd()
				spawn_entity("particle",x+22*cos(angle),y+22*sin(angle),{
					color=14,
					frames_to_death=18
				}):move(x,y,20,ease_out)
			end
		end,
		draw=function(self)
			local x,y,expression=self.x+self.idle_x,self.y+self.idle_y,self.expression
			if boss_health.rainbow_frames>12 then
				x+=scene_frame%2*2-1
			end
			self:apply_colors()
			if self.visible then
				-- draw mirror
				sspr2(115,0,13,30,x-6,y-12)
			end
			if self.visible or boss_health.rainbow_frames>0 then
				-- the face is rainbowified after the player hits a tile
				if boss_health.rainbow_frames>0 then
					if not self.is_reflection then
						color_wash(rainbow_color)
						if expression>0 and boss_phase>0 then
							pal(13,dark_rainbow_color)
						end
					elseif expression==0 then
						color_wash(11)
					end
					expression=8
				end
				-- draw face
				if expression>0 then
					sspr2(11*expression-11,57,11,14,x-5,y-7,false,expression==5 and (self.frames_alive)%4<2)
				end
			end
			pal()
			self:apply_colors()
			if self.visible then
				-- draw top hat
				if self.is_wearing_top_hat then
					sspr2(102,0,13,9,x-6,y-15)
				end
				-- draw laser preview
				if self.laser_preview_frames%2>0 then
					line(x,y+7,x,60,14)
				end
			end
		end,
		on_death=function(self)
			self.left_hand:die()
			self.right_hand:die()
		end,
		apply_colors=function(self)
			-- show or hide crack
			pal(2,ternary(self.is_cracked,6,7))
			-- reflected mirror gets a green tone
			if self.is_reflection then
				color_wash(3)
				pal(7,11)
				pal(6,11)
			end
		end,
		-- highest-level commands
		intro=function(self)
			self:promise_sequence(
				"phase_change",
				spawn_magic_tile,
				function()
					boss_phase+=1
					player_health.visible=true
				end,
				{"return_to_ready_position",nil,"right"},
				"decide_next_action")
		end,
		decide_next_action=function(self)
			local promise=self:promise(1)
			if boss_phase==1 then
				local r=2*rnd_int(0,2)+1
				promise=self:promise_sequence(
					{"set_held_state","right"},
					{"throw_cards",r,"left"},
					{"return_to_ready_position",nil,"left"},
					{"throw_cards",r,"right"},
					{"return_to_ready_position",nil,"left"},
					"shoot_lasers",
					{"return_to_ready_position",nil,"right"})
			elseif boss_phase==2 then
				promise=self:promise_sequence(
					"conjure_flowers",
					"return_to_ready_position",
					"throw_cards",
					"return_to_ready_position",
					"despawn_coins",
					"throw_coins",
					"return_to_ready_position",
					"shoot_lasers",
					"return_to_ready_position")
			elseif boss_phase==3 then
				promise=self:promise_sequence(
					"shoot_lasers",
					"return_to_ready_position",
					"throw_cards",
					"return_to_ready_position",
					"conjure_flowers",
					"return_to_ready_position",
					"despawn_coins",
					"throw_coins",
					"return_to_ready_position")
			elseif boss_phase==4 then
				promise=self:promise_parallel(
						{self,"set_held_state",nil},
						{boss_reflection,"set_held_state",nil})
					:and_then_sequence(
				-- conjure flowers together
					function()
						boss_reflection:promise_sequence(
							"return_to_ready_position",
							32,
							"conjure_flowers",
							"return_to_ready_position")
					end,
					"conjure_flowers",
					25,
					"conjure_flowers",
					"return_to_ready_position",
				-- shoot lasers + throw cards together
					function()
						boss_reflection:promise_sequence(
							"shoot_lasers",
							"return_to_ready_position")
					end,
					"throw_cards",
					"return_to_ready_position",
					100)
				-- throw coins together
					:and_then_parallel(
						"despawn_coins",
						{boss_reflection,"despawn_coins"})
					:and_then_sequence(
					"throw_coins",
					"return_to_ready_position",
					{boss_reflection,"throw_coins",player_reflection},
					"return_to_ready_position",
					{self,100})
			end
			return promise
				:and_then(function()
					-- called this way so that the progressive decide_next_action
					--   calls don't result in an out of memory exception
					self:decide_next_action()
				end)
		end,
		phase_change=function(self)
			local lh,promise=self.left_hand
			if skip_animations then
				if boss_phase==0 then
					self.is_wearing_top_hat=true
				elseif boss_phase==2 then
					player_reflection=spawn_entity("player_reflection")
				elseif boss_phase==3 then
					boss_reflection=spawn_entity("magic_mirror_reflection")
					self.home_x+=20
				end
				return self:promise()
			elseif boss_phase==0 then
				return self:promise_sequence(
					50,
					{lh,"appear"},
					30,
				-- shake finger
					{"set_pose",4},
					6,
					{"set_pose",5},
					6,
					{"set_pose",4},
					6,
					{"set_pose",5},
					6,
					{"set_pose",4},
					10,
				-- grab handle
					{self.right_hand,"appear"},
					15,
					"grab_mirror_handle",
					5,
				-- show face
					{self,"set_expression"},
					33,
					{"set_expression",6},
					25,
					"set_expression",
					33,
					{"set_expression",1},
					30,
				-- tap mirror
					function()
						lh:promise_sequence(
							9,
							{"set_pose",5},
							4,
							{"set_pose",4})	
						lh:promise_sequence(
							{"move",self.x+5*lh.dir,self.y-3,10,ease_out,{0,-10,10*lh.dir,-2}},
							2,
							{"move",lh.x,lh.y,10,ease_in,{10*lh.dir,-2,0,-10}})
					end,
					10,
				-- poof! a top hat appears
					function()
						self.is_wearing_top_hat=true
					end,
					{"poof",0,-10},
					30)
			elseif boss_phase==1 then
				return self:promise_sequence(
					{"return_to_ready_position",2},
					30,
					"set_all_idle",
					10,
				-- pound fists
					{"pound",0},
					{"pound",0},
					{"pound",3},
				-- the bouquet appears!
					{"set_expression",1},
					function()
						lh.is_holding_bouquet=true
						spawn_petals(lh.x,lh.y-6,4,8)
					end,
					{self.right_hand,"set_pose"},
					{"move",20,-10,10,ease_in,{0,-5,-5,0},true},
					35,
				-- sniff the flowers
					{lh,"move",-2,-12,20,ease_in,nil,true},
					{self,"set_expression",3},
					30,
					{self,"set_expression",1},
					15,
				-- they vanish
					function()
						lh:promise_sequence(
							10,
							"set_pose",
							function()
								lh.is_holding_bouquet=false
							end,
							{"move",-18,6,20,ease_in,nil,true})
					end,
					{self.right_hand,"move",0,10,20,ease_out_in,{-25,-20,-25,0},true},
					15,
					{self,"return_to_ready_position"})
			elseif boss_phase==2 then
				return self:promise_sequence(
					{"return_to_ready_position",2},
					"cast_reflection",
					"return_to_ready_position",
					60)
			elseif boss_phase==3 then
				return self:promise_sequence(
					{"return_to_ready_position",2},
					{"cast_reflection",true},
					function()
						boss_reflection:promise("return_to_ready_position",1,"right")
					end,
					{"return_to_ready_position",1,"left"})
			end
		end,
		cancel_everything=function(self)
			self.left_hand:cancel_everything()
			self.right_hand:cancel_everything()
			self:cancel_promises()
			self:cancel_move()
			self.laser_charge_frames,self.laser_preview_frames=0,0
			despawn_boss_entities(entities)
			despawn_boss_entities(new_entities)
		end,
		-- medium-level commands
		pound=function(self,offset)
			return self:promise_parallel(
				{self.left_hand,"pound",offset},
				{self.right_hand,"pound",-offset})
		end,
		reel=function(self,times)
			if boss_phase==3 then
				self.is_cracked=true
			end
			spawn_particle_burst(self.x,self.y,20,7,10)
			local promise,i=self:promise_sequence(
				{"set_expression",8},
				"set_all_idle")
				:and_then_parallel(
					self.left_hand:promise_sequence("set_pose","appear"),
					self.right_hand:promise_sequence("set_pose","appear")
				)
			for i=1,times do
				promise=promise:and_then_sequence(
					function()
						freeze_and_shake_screen(0,3)
						self:poof(rnd_int(-15,15),rnd_int(-15,15))
						self.left_hand:move(rnd_int(-8,8),rnd_int(-8,8),6,ease_out,nil,true)
						self.right_hand:move(rnd_int(-8,8),rnd_int(-8,8),6,ease_out,nil,true)
					end,
					{"move",rnd_int(-8,8),rnd_int(-5,2),6,ease_out,nil,true})
			end
			return promise
		end,
		conjure_flowers=function(self)
			-- generate a list of flower locations
			local locations,i={},0
			while i<40 do
				add(locations,{i%8*10+5,8*flr(i/8)+4})
				i+=rnd_int(1,3)
			end
			-- concentrate
			return self:promise("set_all_idle")
				:and_then_parallel(
					{self.left_hand,"move_to_temple"},
					{self.right_hand,"move_to_temple"})
				:and_then_sequence(
				{"set_expression",2},
			-- spawn the flowers
				function()
					self.flowers={}
					local promise,i=self:promise()
					for i=1,#locations do
						-- shuffle flowers
						local j=rnd_int(i,#locations)
						locations[i],locations[j]=locations[j],locations[i]
						promise=promise:and_then_sequence(
							function()
								add(self.flowers,spawn_entity("flower_patch",locations[i][1],locations[i][2]))
							end,
							1)
					end
				end,
				56,
			-- bloom the flowers
				function()
					local flower
					for flower in all(self.flowers) do
						flower:bloom()
					end
				end,
				{self.left_hand,"set_pose",5},
				{self.right_hand,"set_pose",5},
				{self,"set_expression",3},
				30)
		end,
		cast_reflection=function(self,upgraded_version)
			local lh,rh,i=self.left_hand,self.right_hand
			-- concentrate
			local promise=self:promise_sequence(
				"set_all_idle",
				{"set_expression",2},
				{lh,"move",23,14,20,ease_in,nil,true},
				{"set_pose",1})
			-- wave one hand over the other
			for i=1,2 do
				promise=promise:and_then_sequence(
					{rh,"move",-10,0,20,linear,{0,-3,0,-3},true},
					{"move",10,0,20,linear,{0,3,0,3},true})
			end
			-- poof! the wands appear
			if upgraded_version then
				promise:and_then_sequence(
					{rh,"set_pose",1},
					function()
						rh.is_holding_wand=true
					end,
					{"poof",-10})
			end
			promise=promise:and_then_sequence(
				{self,"set_expression",1},
				function()
					lh.is_holding_wand=true
				end,
				{lh,"poof",10},
				30)
			-- raise the wands to cast a spell
			if upgraded_version then
				promise:and_then(rh,"flourish_wand")
			end
			return promise:and_then_sequence(
				{lh,"flourish_wand"},
				{self,"set_expression",3},
				5,
			-- and finally the spell takes effect
				function()
					if upgraded_version then
						boss_reflection=spawn_entity("magic_mirror_reflection")
						self.home_x+=20
					else
						player_reflection=spawn_entity("player_reflection")
					end
				end,
			-- cooldown
				55)
		end,
		throw_cards=function(self,heart_row,hand)
			heart_row=heart_row or rnd_int(1,5)
			local promises={}
			if hand!="right" then
				add(promises,{self.left_hand,"throw_cards",heart_row})
			end
			if hand!="left" then
				add(promises,{self.right_hand,"throw_cards",heart_row})
			end
			return self:promise_parallel(unpack(promises))
		end,
		throw_coins=function(self,target)
			local promise,i=self.right_hand:promise("move_to_temple")
			for i=1,3 do
				promise=promise:and_then_sequence(
					{self.right_hand,"set_pose",1},
					{self,"set_expression",7},
					"set_all_idle",
					ternary(i==1,24,10),
					function()
						add(self.coins,spawn_entity("coin",self.x+12,self.y,{target=target or player}))
					end,
					{self.right_hand,"set_pose",4},
					{self,"set_expression",3},
					20)
			end
			return promise
		end,
		shoot_lasers=function(self)
			self.left_hand:disappear()
			local promise=self:promise_sequence(
				{"set_held_state","right"},
				"set_expression",
				"set_all_idle")
			local col,i=rnd_int(0,7)
			for i=1,3 do
				col=(col+rnd_int(2,6))%8
				promise=promise:and_then_sequence(
					-- move to a random column
					{"move",10*col+5,-20,15,ease_in,{0,-10,0,-10}},
					-- charge a laser
					function()
						self.laser_charge_frames=10
					end,
					14,
					function()
						self.laser_preview_frames=6
					end,
					6,
					-- shoot a laser
					{"set_expression",0},
					function()
						freeze_and_shake_screen(0,4)
						spawn_entity("mirror_laser",self.x,self.y)
					end,
					14,
					-- cooldown
					"set_expression",
					function()
						self.laser_preview_frames=6
					end,
					6)
			end
			return promise
		end,
		return_to_ready_position=function(self,expression,held_hand)
			local lh,rh,home_x,home_y=self.left_hand,self.right_hand,self.home_x,self.home_y
			lh.is_holding_wand,rh.is_holding_wand=false,false
			-- reset to a default expression/pose
			return self:promise_sequence(
				{"set_all_idle",true},
				{"set_expression",expression or 1},
				{lh,"set_pose"},
				{rh,"set_pose"},
				function()
					if abs(home_x-self.x)>12 or abs(home_y-self.y)>12 then
						return self:set_held_state(held_hand or "either")
					end
				end)
			-- move to home location
				:and_then_parallel(
					{self,"move",home_x,home_y,30,ease_in},
					{lh,"move",home_x-18,home_y+5,30,ease_in,{-10,-10,-20,0}},
					{rh,"move",home_x+18,home_y+5,30,ease_in,{10,-10,20,0}})
			-- reset state
				:and_then_parallel(
					{lh,"appear"},
					{rh,"appear"})
				:and_then(self,"set_held_state",held_hand)
		end,
		set_held_state=function(self,held_hand)
			local promises,primary,secondary={},self.left_hand,self.right_hand
			if held_hand=="right" or (held_hand=="either" and secondary.is_holding_mirror) then
				primary,secondary=secondary,primary
			end
			if secondary.is_holding_mirror then
				add(promises,{secondary,"release_mirror"})
			end
			if primary.is_holding_mirror then
				if not held_hand then
					add(promises,{primary,"release_mirror"})
				end
			elseif held_hand then
				add(promises,{primary,"grab_mirror_handle"})
			end
			return self:promise_parallel(unpack(promises))
		end,
		despawn_coins=function(self)
			local coin
			for coin in all(self.coins) do
				coin:die()
			end
			self.coins={}
			return 10
		end,
		set_all_idle=function(self,idle)
			self.is_idle,self.left_hand.is_idle,self.right_hand.is_idle=idle,idle,idle
		end,
		set_expression=function(self,expression)
			self.expression=expression or 5
		end,
	},
	magic_mirror_reflection={
		extends="magic_mirror",
		render_layer=5,
		visible=true,
		expression=1,
		is_wearing_top_hat=true,
		home_x=20,
		is_reflection=true,
		init=function(self)
			self:super_init()
			self.left_hand:copy_hand(boss.left_hand)
			self.right_hand:copy_hand(boss.right_hand)
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
			local f,m=boss.frames_alive+ternary(self.is_right_hand,9,4),self.mirror
			self.idle_mult=ternary(self.is_idle,min(self.idle_mult+0.05,1),max(0,self.idle_mult-0.05))
			self.idle_x,self.idle_y=self.idle_mult*3*sin(f/60),self.idle_mult*4*sin(f/30)
			self:apply_move()
			if self.is_holding_mirror then
				self.idle_x,self.idle_y,self.x,self.y=m.idle_x,m.idle_y,m.x+2*self.dir,m.y+13
			end
		end,
		draw=function(self)
			local x,y=self.x+self.idle_x,self.y+self.idle_y-8
			if self.visible then
				-- hand may be holding a bouquet
				if self.is_holding_bouquet then
					sspr2(110,71,9,16,x-1,y-4)
				end
				-- reflections get a green tone
				if self.is_reflection then
					color_wash(3)
					pal(7,11)
					pal(6,11)
				end
				-- draw the hand
				local is_right_hand=self.is_right_hand
				sspr2(12*self.pose-12,46,12,11,x-ternary(is_right_hand,7,4),y,is_right_hand)
				-- hand may be holding a wand
				if self.is_holding_wand then
					if self.pose==1 then
						sspr2(91,54,7,13,x+ternary(is_right_hand,-10,4),y,is_right_hand)
					else
						sspr2(98,54,7,13,x-ternary(is_right_hand,3,2),y-8,is_right_hand)
					end
				end
			end
		end,
		copy_hand=function(self,hand)
			self.pose,self.x,self.y,self.visible=hand.pose,hand.x,hand.y,hand.visible
		end,
		-- highest-level commands
		throw_cards=function(self,heart_row)
			local dir,r=self.dir
			local promise=self:promise_sequence(
				8-dir*8,
				function()
					self.is_idle=false
				end)
			for r=ternary(self.is_right_hand,1,2),5,2 do
				promise=promise:and_then_sequence(
					-- move to the correct row
					"set_pose",
					{"move",40+50*dir,8*r-4,18,ease_out_in,{10*dir,-10,10*dir,10}},
					{"set_pose",2},
					6,
					-- throw the card
					{"set_pose",1},
					function()
						spawn_entity("playing_card",self.x-10*dir,self.y,{
							vx=-1.5*dir,
							has_heart=(r==heart_row)
						})
					end,
					6,
					-- pause
					{"set_pose",2},
					3)
			end
			return promise
		end,
		flourish_wand=function(self)
			return self:promise_sequence(
				{"move",40+20*self.dir,-30,12,ease_out,{-20,20,0,20}},
				{"set_pose",6},
				function()
					spawn_particle_burst(self.x,self.y-20,20,3,10)
					freeze_and_shake_screen(0,20)
				end)
		end,
		grab_mirror_handle=function(self)
			return self:promise_sequence(
				"set_pose",
				{"move",self.mirror.x+2*self.dir,self.mirror.y+13,10,ease_out,{10*self.dir,5,0,20}},
				{"set_pose",2},
				function()
					self.is_holding_mirror=true
				end)
		end,
		cancel_everything=function(self)
			self:cancel_promises()
			self:cancel_move()
			self.is_holding_wand,self.is_holding_mirror=false -- ,nil
		end,
		release_mirror=function(self)
			self.is_holding_mirror=false
			return self:promise_sequence(
				"set_pose",
				{"move",15*self.dir,-7,25,ease_in,nil,true})
		end,
		appear=function(self)
			if not self.visible then
				self.visible=true
				return self:poof()
			end
		end,
		disappear=function(self)
			self.visible=false
			return self:poof()
		end,
		pound=function(self,offset)
			local mirror=self.mirror
			return self:promise_sequence(
				{"set_pose",2},
			-- move out
				{"move",mirror.x+20*self.dir,mirror.y+20,10,ease_in},
			-- move in
				{"move",mirror.x+ternary(offset==0,4,0)*self.dir,mirror.y+20+offset,5,ease_out},
			-- pound!
				function()
					freeze_and_shake_screen(0,2)
				end,
				1)
		end,
		move_to_temple=function(self)
			return self:promise_sequence(
				{"set_pose",1},
				{"move",self.mirror.x+13*self.dir,self.mirror.y,20})
		end,
		set_pose=function(self,pose)
			if not self.is_holding_mirror then
				self.pose=pose or 3
			end
		end
	},
	mirror_laser={
		hitbox_channel=1, -- player
		is_boss_generated=true,
		render_layer=9,
		frames_to_death=14,
		draw=function(self)
			local x,y=self.x,self.y+4
			rectfill(x-5,y,x+5,100,14)
			rectfill(x-4,y,x+4,100,15)
			rectfill(x-3,y,x+3,100,7)
		end,
		is_hitting=function(self,entity)
			return self:col()==entity:col()
		end
	},
	heart={
		frames_to_death=150,
		hurtbox_channel=2, -- pickup
		draw=function(self)
			local f=self.frames_to_death
			if f>30 or f%4>1 then
				if (f+4)%30>14 then
					pal(14,8)
				end
				sspr2(ternary(f%30<20,36,45),30,9,7,self.x-4,self.y-5-max(0,self.frames_alive-0.09*self.frames_alive*self.frames_alive))
			end
		end,
		on_hurt=function(self)
			freeze_and_shake_screen(2,0)
			player_health:gain_heart()
			spawn_particle_burst(self.x,self.y,6,8,4)
			self:die()
		end
	},
	poof={
		frames_to_death=12,
		render_layer=9,
		draw=function(self)
			sspr2(64+16*flr(self.frames_alive/3),31,16,14,self.x-8,self.y-8)
		end
	},
	pain={
		is_pause_immune=true,
		render_layer=12,
		frames_to_death=5,
		draw=function(self)
			pal(7,10)
			if self.frames_to_death<=2 then
				palt(10,true)
			end
			sspr2(105,45,23,26,self.x-11,self.y-16)
		end
	},
	points={
		render_layer=10,
		vy=-0.5,
		frames_to_death=30,
		draw=function(self)
			pset(self.x,self.y,8)
			local text="+"..self.points.."00"
			print(text,self.x-2*#text,self.y,rainbow_color)
		end
	}
}

-- primary pico-8 functions (_init, _update, _draw)
function _init()
	scene_frame,freeze_frames,screen_shake_frames,is_paused=0,0,0 -- ,false
	calc_rainbow_color()
	init_game()
end

-- local skip_frames=0
function _update()
	-- skip_frames=increment_counter(skip_frames)
	-- if skip_frames%1>0 then return end
	if freeze_frames>0 then
		freeze_frames=decrement_counter(freeze_frames)
		if player then
			player:check_inputs() -- todo other scenes won't like this
		end
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
		update_game()
	end
end

function _draw()
	-- clear the screen
	cls()
	-- call the draw function of the current scene
	draw_game()
	-- draw debug info
	-- camera()
	-- print("mem:      "..flr(100*(stat(0)/1024)).."%",2,102,ternary(stat(1)>=819,8,3))
	-- print("cpu:      "..flr(100*stat(1)).."%",2,109,ternary(stat(1)>=0.8,8,3))
	-- print("entities: "..#entities,2,116,ternary(#entities>120,8,3))
	-- print("promises: "..#promises,2,123,ternary(#promises>30,8,3))
end


-- game functions
function init_game()
	-- reset everything
	entities,new_entities,score,score_mult,boss_phase={},{},0,1,0
	-- create starting entities
	-- player_health,player,player_reflection=spawn_entity("player_health"),spawn_entity("player",35,20) -- ,nil
	title_screen=spawn_entity("title_screen")
	left_curtain=spawn_entity("curtain",1)
	right_curtain=spawn_entity("curtain",125,0,{dir=-1})
	-- boss_health,boss,boss_reflection=spawn_entity("boss_health") -- ,nil,nil
	-- -- show controls
	-- if boss_phase==0 then
	-- else
	-- 	-- skip to certain phase of the fight (for debug purposes)
	-- 	boss=spawn_entity("magic_mirror")
	-- 	boss.visible,boss_health.visible=true,true
	-- 	if boss_phase>1 then
	-- 		boss:set_expression(1)
	-- 		boss.is_wearing_top_hat=true
	-- 		boss.right_hand:appear()
	-- 		boss.left_hand:appear()
	-- 	end
	-- 	if boss_phase>3 then
	-- 		player_reflection=spawn_entity("player_reflection")
	-- 	end
	-- 	boss_phase-=1
	-- 	boss:promise_sequence(
	-- 		"phase_change",
	-- 		function()
	-- 			boss_phase+=1
	-- 		end,
	-- 		"return_to_ready_position",
	-- 		"decide_next_action")
	-- end
	-- immediately add new entities to the game
	add_new_entities()
end

function update_game()
	-- sort entities for updating
	sort_list(entities,function(a,b)
		return a.update_priority>b.update_priority
	end)
	-- update entities
	local entity
	for entity in all(entities) do
		if not is_paused or entity.is_pause_immune then
			-- call the entity's update function
			entity:update()
			-- do some default update stuff
			decrement_counter_prop(entity,"invincibility_frames")
			entity.frames_alive=increment_counter(entity.frames_alive)
			if decrement_counter_prop(entity,"frames_to_death") then
				entity:die()
			end
		end
	end
	-- check for hits
	if not is_paused then
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
	end
	-- add new entities to the game
	add_new_entities()
	-- remove dead entities from the game
	filter_out_finished(entities)
	-- sort entities for rendering
	sort_list(entities,function(a,b)
		return ternary(a.render_layer==b.render_layer,a:row()>b:row(),a.render_layer>b.render_layer)
	end)
end

function draw_game()
	-- shake the camera
	local shake_x=0
	if freeze_frames<=0 and screen_shake_frames>0 then
		shake_x=ternary(boss_phase==5,1,ceil(screen_shake_frames/3))*(scene_frame%2*2-1)
	end
	-- draw the background
	camera(shake_x,-11)
	-- draw stars
	local stars,i={29,19,88,7,18,41,44,3,102,43,24,45,112,62,11,70,5,108,120,91,110,119}
	circ(18,41,1,1)
	circ(112,62,1)
	for i=1,#stars,2 do
		pset(stars[i],stars[i+1])
	end
	-- draw tiles
	camera(shake_x-23,-65)
	rectfill(0,-1,80,41,1)
	local c,r
	for c=0,7 do
		for r=0,4 do
			sspr2(83+(c+r)%2*11,45,11,9,10*c,8*r)
		end
	end
	-- draw some other grid stuff
	local x
	for x=0,70,10 do
		sspr2(77,10,11,7,x,42)
	end
	sspr2(83,54,4,2,0,-1,false,true)
	sspr2(83,54,4,2,77,-1,true,true)
	sspr2(83,54,4,2,0,40,false)
	sspr2(83,54,4,2,77,40,true)
	pal()
	-- draw entities
	foreach(entities,function(entity)
		if not entity.is_user_interface then
			entity:draw()
			pal()
		end
	end)
	-- draw ui
	camera(shake_x)
	-- -- draw black boxes
	-- rectfill(0,0,127,10,0)
	-- rectfill(0,118,127,128)
	if boss_phase>0 then
		-- draw score multiplier
		sspr2(72,45,11,7,6,2)
		print(score_mult,8,3,0)
		-- draw score
		local score_text=ternary(score>0,score.."00","0")
		print(score_text,121-4*#score_text,3,1)
	end
	-- print("25700",101,3,1)
	-- -- draw lives
	-- sspr2(73,52,10,5,7,120)
	-- print("3",19,120)
	-- -- draw timer
	-- print("17:03",101,120)
	-- draw ui entities
	pal()
	foreach(entities,function(entity)
		if entity.is_user_interface then
			entity:draw()
			pal()
		end
	end)
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

-- particle functions
function spawn_particle_burst(x,y,num_particles,color,speed)
	local particles,i={}
	for i=1,num_particles do
		local angle,particle_speed=(i+rnd(0.7))/num_particles,speed*rnd_num(0.5,1.2)
		add(particles,spawn_entity("particle",x,y,{
			vx=particle_speed*cos(angle),
			vy=particle_speed*sin(angle)-speed/2,
			color=color,
			gravity=0.1,
			friction=0.75,
			frames_to_death=rnd_int(13,19)
		}))
	end
	return particles
end

function spawn_petals(x,y,num_petals,color)
	local i
	for i=1,num_petals do
		spawn_entity("particle",x,y-2,{
			vx=i-0.5-num_petals/2,
			vy=rnd_num(-2,-1),
			friction=0.9,
			gravity=0.06,
			frames_to_death=rnd_int(10,17),
			color=color
		})
	end
end

-- magic tile functions
function spawn_magic_tile(frames_to_death)
	if boss_health.health>=60 then
		boss_health.drain_frames=60
	end
	spawn_entity("magic_tile_spawn",10*rnd_int(1,8)-5,8*rnd_int(1,5)-4,{
		frames_to_death=frames_to_death or 100
	})
end

function on_magic_tile_picked_up(tile,health)
	health+=boss_health.health
	if health<60 and boss_phase<5 then
		spawn_magic_tile(ternary(boss_phase<1,80,120)-min(tile.frames_alive,30)) -- 30 frame grace period
	end
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
				if not self.finished then
					self:on_death()
					self.finished=true
				end
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
			end,
			-- shared methods tacked on here to save tokens
			poof=function(self,dx,dy)
				spawn_entity("poof",self.x+(dx or 0),self.y+(dy or 0))
				return 12
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

function despawn_boss_entities(list)
	foreach(list,function(entity)
		if entity.is_boss_generated then
			entity:despawn()
		end
	end)
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

-- drawing functions
function calc_rainbow_color()
	local f=flr(scene_frame/4)%6
	rainbow_color=8+f
	if rainbow_color==13 then
		rainbow_color=14
	end
	dark_rainbow_color=({2,4,9,3,13,8})[f+1]
end

function sspr2(x,y,width,height,x2,y2,flip_horizontal,flip_vertical)
	sspr(x,y,width,height,x2+0.5,y2+0.5,width,height,flip_horizontal,flip_vertical)
end

function color_wash(c)
	local i
	for i=1,15 do
		pal(i,c)
	end
end

-- tile functions
function get_tile_occupant(col,row)
	local e
	for e in all(entities) do
		if e.occupies_tile and e:col()==col and e:row()==row then
			return e
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

function ease_out_in(percent)
	return ternary(percent<0.5,ease_out(2*percent)/2,0.5+ease_in(2*percent-1)/2)
end

-- function ease_in_out(percent)
-- 	return ternary(percent<0.5,ease_in(2*percent)/2,0.5+ease_out(2*percent-1)/2)
-- end

-- helper functions
function freeze_and_shake_screen(f,s)
	freeze_frames,screen_shake_frames=max(f,freeze_frames),max(s,screen_shake_frames)
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
00000ccccc00cc00000000000000cccc000000ccccc0000900cc00000000000000000000ccc000000c0000000000ccccc000020005555555000000000f000000
0000cccccccccccccccc0000000cccccc0000ccccccc0008dccccc000000000000000000ccc000000c0c0000000ccccccc000200055555650000000090f00000
0000cccc1c1cccc1111c1c0000ccc11c10000cccc1c10000cccccc0000c11cccc000000cc1c00000ccccc00000cc11c11cc00200055555650000000090f00000
0000cdcc1c1cddd1111c1c00cddcc11c10000dccc1c1000dcc1c1cc0ccc11111cc000ddcc1c00d0ccccccc00ddcccccccccdd200055555650000009094f09000
0000cccccccccccccccccc000cccccccc0000ccccccc00ddcc1c1cc0ccddcccccc00000cccc000dcccc11c0d00ccccc002222200055555550000094499944900
0000ddcccccddcdddd00000000ddccddc0000ddcccdc000ddccccc0ddccccccdd000000dccc000ccc1c11cd00ccccccc02222200055555550000009977799000
0000ddddddddddd0000000000ddddddd0000dddddddd0000ddcccd0ddddddd000000000dddd00000ccccccc0dc11c11cd2222210088888880010097777777900
00000d000d00d00000000000000000d00000000000d000000d0009800000d000000000d000d000dcccccc0000dcccccd022222555555555555509777777777f0
000ccccc00000000c00000000ccccc000000ccccc000000ccccc000000000000000000000000000ddddddd000ccccccc022222055555555555009777777777f0
00ccccccc000000ccc0000000ccccc00000ccccccc0090ccccccc090000000000000000000000000d000d0000dcccccd0222005555555555600977777777777f
00ccccccc000000ccc000000ccccccc0000ccccccc000dcccccccd00d0000000d00d0000000d0101010101010ddddddd0222155511111115561977777777777f
00dcccccd000000ccc000000ccccccc0000dcccccd0080cdddddc080dcccccccd00cdcccccdc00101010101000d000d002225511111111111659777777777779
00ccccccc00000ccccc00000dcccccd0000ccccccc0000ddddddd000dcccccccd00ccccccccc0000000000000000d00022225551111111115559777777777779
00cdddddc00000dcccd00000dcdddcd0000cdddddc0000ddddddd000cdddddddc00ddddddddd0101010101010000dd0022225055551115555059777777777779
00ddddddd00000dcccd00000ddddddd0000ddddddd00000ddddd0000ddddddddd0000ddddd00000000000000ddddddd022220088555555588009777777777779
000d000d000000cdddc00000ddddddd00000000d00000000d00000000ddddddd00000d000d00000000000000dddddddd22220055888888855000977777777790
0000000000000ddddddd0000000ddd0000000000000000000000000000000000000000000000000100001000ddddddd022220055555555555000977777777790
0000000000000ddddddd00000000d000000000000000000000000000000000000000000000000222222222220000dd0022220055555555555000047777777400
00000000000000d000d000000000d000000000000000000000000000000000000000000000000222222222220000d000222200555555555550009949777949f0
00000000000000ccccc0000000000000000000000000000000000000000000000000000000000222222222222222222222220005555555550000944999994490
0000000000000ccccccc0000000c0000000000000000000000000000000000000000000000000222222222222222222222220000055555000000099494949900
0000000000000cc1c1cc000000cc0c00000000000000000000000000000000000000000000000000006000000000000000000600000000000000000094900000
000ccccc000000c1c1c000000ccccc000000ccccc000000000000000000ccc000000000000000000077700000000000000007770000006777760000099900000
00ccccccc00000c1c1d00000cc1c1cc0000ccccccc00000ccccc000000c1c1c00000000000000000775770006777777600077777000007577770000009000000
00cc1c1cc00000c1c1d00000cc1c1cd0000cc1c1cc0090ccccccc09000c1c1c00000000000000007777777007777775700777777700007777770000009000000
00dc1c1cd00000d1c1d00000cd1c1cd0000cc1c1cd000dcccccccd00ddc1c1cd00d00ccccc00d077755777607775577706757557770007755770000009000000
00ccccccc00000ddccc00000ddccccc0000cdccccc0080ccccccc080dcc1c1cdd00dcccccccd0677755777007775577700777557576007755770000099f00000
00dcccccd000000ddd000000dcccccc0000dcccccc0000cc1c1cc000ccc1c1ccd00cc11c11cc0077777770007577777700077777770007777770000099f00000
00ddddddd000000ddd000000ddddddd0000ddddddd0000cc1c1cc000ccc1c1ccc00ccccccccc0007757700006777777600007777700007777570000049900000
000d000d00000000d00000000d0000000000d0000000000ccccc000000dddddd0000000000000000777000000000000000000777000006777760000004000000
00000000000000000080000000880000000800000000000000000008800000022222222222222000060000000000000000000060000000000000022222222222
00550550000550550008880888000880880000880880000088800088880588020000000000000000000000000000000000007770000000000000070000000000
05005005005005005008888ee8008888ee8008888ee80008888e00888050ee820000000000000000000077700000000000007770000000000000000007000000
05000005005888885008888ee8008888ee8008888ee80008888e00088808ee820000000000000000000777700000000000070000770000000000000000000007
00500050000588850000888880000888880000888880000888880000800088020000000000000000000777007700000000000000770007770070000000000000
00050500000058500000888880000088800000088800000088800000050880020000077077700000000000007700777000770000000007770000000000000000
00005000000005000008008008008008008000008000000008000000005800020000077777770000007700000000777700770000000070000000000000000000
00000000000000000000000000000dddd00000666660000666d60022222222220000777777770000007770000077077700000000007700000000000000070000
0000000000000000000000000000dddddd000666d77600d66d776027777777770000777777770000007770077770000000007000777700000000000000000000
000000000000dd0000660000000dddddddd0666ddd77666dddd77627555555570007777777777000000000777777000000000000777700000000000007000007
00660000000dddd000666600000dddddddd0666d66676666d6667627577777570007777777777000000000777777000000000070077700777000000000000000
00006600000dddd000006666000dddddddd0666ddd666666ddd66627575557570007777770777000007700077777077077700000000000770000000000000000
000000000000dd0000000066660dddddddd0d666d666dd6d6d6d6d27577777570000777700000000777770000000077077700000000007000000000000000000
0000000000000000000000006600dddddd00dd66666dddd66666dd27555555570000777000000000777770077000077000707077000000000000000000000000
00000000000000000000000000000dddd0000d5ddddd00d5dddd5027777777770000000000000000077000077000000000000000000000000000000000000000
000000000000000000000000000000000000005d5d50000555d50022222222222222222201111111110511111111155111111111500000000000000000000700
00000000000000000000000000000000000000770000000000000070000007700000000011111111111115555555111155555551100000000000000000007000
00000000000000000000000000007700000000777000000000000770000007700770000011111101011155111115511551111155100000000000000700007000
00000000000000000000000000007700000000077000000000000770000007770770000011111110111151115111511511151115100000000000000700070000
0000000000000000000000000770077000000007770000000000077000000077066000001111110101115115151151151155511510000000000000a000aa0000
0000776777770000777000000777067000000000770770000000077000000076777000001111111111115111511151151115111510000700000000aa0aa00000
00d77777777700d77777700000677067007700776677700000777770770000077770000001111111110155111115511551111155100000a000000aaaaaa00000
00d77dd7600000d77dd770007706676677770777767700000077767777000007667000002ddddd00000115555555111155555551100000aaa000000aaa000077
00d77777777700d7777770007777666677600776767700000076767770000007777000002d0d0d001015111111111551111111115000000a00000000aaaaaa00
00d77dd7777700d77dd770000066666666000067677700000066677600000007776d00002d0d0d0001050002222550000000000000000000000000000aaa0000
00d67777700000d67777600000006666dd000006666d0000006676600000000066dd000025ddd500101555522225500000006600000000000000000000a00000
000066660000000066660000000000ddd000000066d00000000dddd000000000ddd000002ddddd00000222222225550000006600000000000000000000a00000
00006660000000066600000000666000000007770000000076600000000cbb000000006660000000066600002220550000005500000000000000000000000000
006666666000066666660000777772700007777776000067667770000accbbee0000666666600007777727002220000000006600000000000000000000000000
07777772770077766627700ddd772ddd007777766770067677676700aaccbbee80077777dd7700ddd772ddd02220000000005500000000a00000000000000000
0ddd772ddd0077777727700777772777007776677660077676767600aaccbbee800dd77277d70077777277702220055500005500000000a00000000000000000
7777772777777dd772dd7777d77772d7777667766666676766766776aaccbbee887777727777777d77772d77222000550000550000000aaa0000000000000000
77d77772d777776d7d67777d7d772d7d766776666677767677677666aaccbbee887d77772d7767ddd772ddd72220005550005500000aaaaaa00000000a000000
7d7d772d7d7777777727777777722777777666667777677676766776aaccbbee88d7d772d7d7677d77227d7722200006600055000770000aaa000000aaa00000
77d77227d777d7d772d7d777ddddddd7766666777776767767777676aaccbbee887d77227d777777727727772220000555005500000000aaaaaa000000a00000
7777277277777d77227d7777ddddddd7766677777667776776767766aaccbbee8877727727777777ddddd7772220000066005500000000aa0aa0000000070000
77d72777d777777277277777ddddddd776777776677767676767766111ee11cc117772dd7777777ddddddd77222000006600000000000aa000a0000000000000
07ddddddd70077ddddd770077ddddd7700777667777006766676670011ee11cc1007dddd7777007d72777d702222222222222222200007000700000000000000
06772777760077d277d7700667277766007667777770076776767600ddddddddd006727777760067727777602222222222222222200070000700000000000000
006677766000077277770000666666600007777777000076776670000ddddddd0000667776600006666666002222222222222222200070000000000000000000
00006660000000066600000000666000000007770000000076700000000ddd000000006660000000066600002222222222222222200700000000000000000000
000066666660666600006600066666666600666666666660009f0777000002222222222222222222222222222222222222222000000000088000800000030000
00000066060060600006666066600000666066006060066009ff7ff7000002222222222222222222222222222222222222222880000088888b088e0088030880
000000060600606000060660660000000660600060600060fff7f7f00000022222222222222222222222222222222222222228188888188883b8888088008880
000000060600606000000060666000060660060060600660f77f7f00000002222222222222222222222222222222222222222080000080bb3133880008838000
000000060600606000000060060600006600660060600600777777777700022222222222222222222222222222222222222220800800800088833b0330383000
00000006060060600000006000606000000000006060000777777777777ff2222222222222222222222222222222222222222080000080038e8b000008830000
00000006060060600000006000060600000000006060000777077777777ff22222222222222222222222222222222222222228188888183b888bb00008800300
000000060600606000000060000060600000000060600007e7777777777702222222222222222222222222222222222222222880000088000b30000000000030
000000060600606000000060000006060000000060600000777777777777022222222222222222222222222222222222222222222222220003b0000222222222
06600006060060600000006006600060600000006060000fff777f777777022222222222222222222222222222222222222222222222220003b0000222222222
66660006060060600000006066660006060000006060000ff07700f9777772222222222222222222222222222222222222222222222222000330000222222222
6606000606006060000000606606000066600000606000000000000f997772222222222222222222222222222222222222222222222222000330000222222222
60000006060060600000006060000000066000006060000000000000ff0772222222222222222222222222222222222222222222222222000310000222222222
60000006660060600000006066000000066000006060000222222222222222222222222222222222222222222222222222222222222222000130000222222222
0d000dddd0000ddd00000d00ddd00000ddd00000d0d0000222222222222222222222222222222222222222222222222222222222222222000130000222222222
00dddddd000000ddddddd0000ddddddddd00000ddddd000222222222222222222222222222222222222222222222222222222222222222000130000222222222
22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222
00006666666000006666600000066000666666666666666222222222222222222222222222222222222222222222222222222222222222222222222222222222
00066600000600000666600000666600606660000000066222222222222222222222222222222222222222222222222222222222222222222222222222222222
00666000000060000666660000606600606600000000066222222222222222222222222222222222222222222222222222222222222222222222222222222222
06066000000066000660660000000600606600000000660222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060000000066000660666000000600606600000000066222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060000000006000666066000000600606600000000000222222222222222222222222222222222222222222222222222222222222222222222222222222222
60660000000006600606066600000600606600000000000222222222222222222222222222222222222222222222222222222222222222222222222222222222
60660000000006600606606600000600606600000000000222222222222222222222222222222222222222222222222222222222222222222222222222222222
60660000000006600600606660000600606600000000000222222222222222222222222222222222222222222222222222222222222222222222222222222222
60660000000006600600660660000600606600000600000222222222222222222222222222222222222222222222222222222222222222222222222222222222
60660000000006600600060666000600606666666600000222222222222222222222222222222222222222222222222222222222222222222222222222222222
60660000000006600600066066000600606600000600000222222222222222222222222222222222222222222222222222222222222222222222222222222222
60660000000006600600006066600600606600000000000222222222222222222222222222222222222222222222222222222222222222222222222222222222
60660000000006600600006606600600606600000000000222222222222222222222222222222222222222222222222222222222222222222222222222222222
60660000000006600600000606660600606600000000000222222222222222222222222222222222222222222222222222222222222222222222222222222222
60660000000006600600000660660600606600000000000222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060000000006000600000060666600606600000000660222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060000000066000600000066066600606600000006600222222222222222222222222222222222222222222222222222222222222222222222222222222222
06066000000066000600000006066600606600000006660222222222222222222222222222222222222222222222222222222222222222222222222222222222
00666000000060000600000006606600606600000000666222222222222222222222222222222222222222222222222222222222222222222222222222222222
000ddd00000d00000dd0000000d0dd00d0ddd00000000dd222222222222222222222222222222222222222222222222222222222222222222222222222222222
0000ddddddd00000dddd000000dddd00ddddddddddddddd222222222222222222222222222222222222222222222222222222222222222222222222222222222
00000000000000000000000000000000000000000000000222222222222222222222222222222222222222222222222222222222222222222222222222222222
00000000000000000000000000000000000000000000000222222222222222222222222222222222222222222222222222222222222222222222222222222222
66666660000000066666000006666666660006666666660222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060006600006666000660066600000666066600000666222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060006600006060000060066000000066066000000066222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060000660006060000060066600006066066600006066222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060000660060600000006006060000660006060000660222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060000660060600000006000606000000000606000000222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060006600060600000006000060600000000060600000222222222222222222222222222222222222222222222222222222222222222222222222222222222
06066666000060600000006000006060000000006060000222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060000600060600000006000000606000000000606000222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060000660060600000006006600060600006600060600222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060000066060600000006066660006060066660006060222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060000066060600000006066060000666066060000666222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060000066006060000060060000000066060000000066222222222222222222222222222222222222222222222222222222222222222222222222222222222
06060000066006060000060066000000066066000000066222222222222222222222222222222222222222222222222222222222222222222222222222222222
0d0d0000dd000dddd000dd00ddd00000ddd0ddd00000ddd222222222222222222222222222222222222222222222222222222222222222222222222222222222
dddddddd0000000ddddd00000ddddddddd000ddddddddd0222222222222222222222222222222222222222222222222222222222222222222222222222222222

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


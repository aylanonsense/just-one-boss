pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
--just one boss
--by bridgs

-- set cart data (for saving and loading high scores)
cartdata("bridgs_justoneboss_3_test")

--[[
cart data:
	0:	high score
	1:	best time in seconds
	2:	high score (hard mode)
	3:	best time in seconds (hard mode)

sound effects:
	0:	player teeter -> player step / boss bouquet appear / disappear
	1:	menu advance / heart collect
	2:	tile spawn
	3:	tile collect -> tile particle connect (ten tones)
	4:	poof
	5:	boss static -> test screen -> static
	6:	boss laser charge -> boss laser
	7:	player hurt -> boss pound / boss reel explosion
	8:	coin spawn
	9:	coin pound (two pounds) -> player bump
	10:	hand throw card
	11:	flower spawn / hand grab handle
	12:	flower bloom / boss cast spell
	...	title screen music - fun, simple, loops
	...	intro music - mysterious, slow, simple, loops
	...	boss music - high-energy, fast-paced, loops
	...	death jingle - sad, no loop
	...	victory music - happy, high-energy, loops

audio channels:
		music		sfx
	0:	-			player hurt / boss sounds (high priority), player sounds (low priority)
	1:	melody
	2:	harmony
	3:	percussion	tile sounds

coordinates:
  +x is right, -x is left
  +y is down / towards the screen, -y is up / away from the screen
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
	sound effects + music
	hard mode
	gameplay tweaks
	playtesting

expected tokens for music/sound effects: 113
that means token limit before sounds is: 8079

32 tokens can be saved by getting rid of skip_title_screen
41 tokens can be saved by getting rid of skip_phase_change_animations
~2 tokens can be saved by moving rainbow_frames off of boss_health
~50 tokens can be saved by making decide_next_action use the spritesheet for data
~19 tokens can be saved by combining despawn_coins with throw_coins
~10 tokens can be saved by using rnd_dir() in places were it's appropriate
~5 tokens can be saved by switching spawn_entity to have default args, e.g. {x,y,vx=vx,vy=vy}
~8 tokens can be saved by converting more props to sprite flag data
-----------------------
167 tokens can be saved
7770 estimated final token count

4 tokens saved by changing small sprites to use spr()
44 tokens saved by reducing argument usage on return_to_ready_position
43 tokens saved by converting render_layer into sprite flag data
24 tokens saved by converting frames_to_death into sprite flag data
13 tokens saved by converting is_boss_generated into sprite flag data

i have 31 entities
there are 255 sprites

255/31

186
trying to beat 8020


where are tokens being used?
	magic_mirror class				2262 tokens
		decide_next_action method		237 tokens
		phase_change method				398 tokens
	other classes					1523 tokens
	global utility functions		988 tokens
	player class					685 tokens
	screen classes					662 tokens
	spawn_entity funtion			614 tokens
	magic_mirror_hand class			555 tokens
	primary pico-8 functions		487 tokens
	magic_tile class				357 tokens
	global variable declarations	48 tokens

todo: ease_in_out does not exist?
]]

-- useful noop function
function noop() end

-- global debug vars
local starting_phase,skip_phase_change_animations,skip_title_screen=1,false,false

-- global scene vars
local next_reflection_color,scene_frame,freeze_frames,screen_shake_frames,timer_seconds,score_data_index,time_data_index,rainbow_color,boss_phase,score,score_mult,is_paused,hard_mode=1,0,0,0,0,0,1,8,0,0,1 -- ,false,false

-- global entity vars
local promises,entities,title_screen,player,player_health,player_reflection,player_figment,boss,boss_health,boss_reflection,curtains={} -- ,nil,...

-- global entities classes
local entity_classes={
	-- entity 1: top_hat [sprite data 0-5]
	{
		-- draw
		function(self)
			self:draw_sprite(7,1,100,9,15,12)
		end,
		-- update
		function(self)
			if self.frames_alive%15==0 then
				-- entity 3: bunny
				spawn_entity(3,self,nil,{vx=rnd_dir()*(1+rnd(2)),vy=-1-rnd(2)}):poof()
			end
		end
	},
	-- entity 2: spinning_top_hat [sprite data 6-11]
	{
		-- draw
		function(self)
			-- local c,r=self:col(),self:row()
			-- rectfill(10*c-10,8*r-8,10*c,8*r,10)
			pal(5,self.parent.dark_color)
			pal(6,self.parent.light_color)
			pal(8,self.parent.light_color)
			self:draw_sprite(7,10,100,9,15,12)
		end,
		-- update
		function(self)
			if not self.movement then
				self.x+=2*cos(self.frames_alive/50)
			end
		end,
		hitbox_channel=1, -- player
		vy=1
	},
	-- entity 3: bunny [sprite data 12-17]
	{
		-- draw
		function(self)
			self:draw_sprite(7,7,87,67,14,12,self.vx>0)
		end,
		-- update
		function(self)
			self.vy+=0.1
		end
	},
	-- entity 4: curtains [sprite data 18-23]
	{
		-- draw
		function(self)
			self:draw_curtain(1,1)
			self:draw_curtain(125,-1)
		end,
		-- update
		function(self)
			decrement_counter_prop(self,"anim_frames")
			self.amount_closed=62*ease_out_in(self.anim_frames/100)
			if self.anim!="open" then
				self.amount_closed=62-self.amount_closed
			end
		end,
		is_pause_immune=true,
		-- amount_closed=62,
		anim_frames=0,
		draw_curtain=function(self,x,dir)
			rectfill(x-10*dir,0,x+dir*self.amount_closed,127,0)
			local x2
			for x2=10,63,14 do
				local x3=x+0.5+dir*x2*(1+self.amount_closed/62)/2
				line(x3,11,x3,60+40*cos(x2/90-0.02),2)
			end
		end,
		set_anim=function(self,anim)
			self.anim,self.anim_frames=anim,100
		end
	},
	-- entity 5: screen [sprite data 24-29]
	{
		-- draw
		noop,
		-- update
		function(self)
			self:check_for_activation()
		end,
		x=63,
		is_pause_immune=true,
		check_for_activation=function(self)
			if self.frames_alive>self.frames_until_active and not self.is_activated then
				if btnp(1) then
					self.is_activated=true
					slide(self):on_activated()
				else
					return true
				end
			end
		end,
		draw_prompt=function(self,text)
			if self.frames_alive%30<22 and self.frames_alive>self.frames_until_active and not self.is_activated then
				text="press    to "..text
				print_centered(text,63,99,13)
				spr(190,87-2*#text,98)
				return true
			end
		end,
		on_activated=noop
	},
	-- entity 6: title_screen [sprite data 30-35]
	{
		-- draw
		function(self)
			self:draw_sprite(23,-26,0,71,47,16)
			self:draw_sprite(23,-44,0,88,47,40)
			-- hard mode prompt
			if self:draw_prompt("begin") and dget(0)>0 then
				pal(13,8)
				print_centered("or    for hard mode",63,108)
				-- spr(190,36,107,true)
				spr(190,36,107,1,1,true)
			end
		end,
		-- update
		function(self)
			if self:check_for_activation() and btnp(0) then
				self.is_activated,hard_mode,score_data_index,time_data_index=true,true,2,3
				slide(self,-1):on_activated()
			end
		end,
		extends=5, -- entity 5: screen
		frames_until_active=5,
		on_activated=function()
			curtains:promise_sequence(
				ternary(skip_title_screen,0,27),
				{"set_anim","open"},
				function()
					local n=30
					if skip_title_screen then
						curtains.anim_frames,n=0,0
					end
					entities,boss_phase,score,score_mult,timer_seconds,is_paused={title_screen,curtains},max(0,starting_phase-1),0,1,0 -- ,false
					-- entity 11: player
					-- entity 12: player_health
					-- entity 13: boss_health
					player,player_health,boss_health,player_reflection,player_figment,boss,boss_reflection=spawn_entity(11),spawn_entity(12),spawn_entity(13) -- ,nil,...
					-- hard_mode=true -- todo debug remove
					if starting_phase>0 then
						-- entity 22: magic_mirror
						boss=spawn_entity(22)
						boss.visible,boss_health.visible=true,true
						boss:promise_sequence(n,"intro")
						-- todo remove debug schtuff -> 19 tokens
						if starting_phase>1 then
							boss.is_wearing_top_hat=true
						end
						if starting_phase>3 then
							-- entity 16: player_reflection
							player_reflection=spawn_entity(16)
						end
					else
						spawn_magic_tile(150+n)
					end
				end)
		end
	},
	-- entity 7: credit_screen [sprite data 36-41]
	{
		-- draw
		function(self,x)
			print_centered("thank you for playing!",x,28,rainbow_color)
			print_centered("created (with love) by bridgs",x,73,6)
			print_centered("https://brid.gs",x,83,12)
			self:draw_sprite(11,-43,ternary_hard_mode(70,48),80,22,16)
			self:draw_prompt("continue")
		end,
		extends=5, -- entity 5: screen
		x=188,
		frames_until_active=130,
		on_activated=function(self)
			show_title_screen()
		end
	},
	-- entity 8: victory_screen [sprite data 42-47]
	{
		-- draw
		function(self,x,y,f)
			-- congratulations
			if hard_mode then
				pal(9,8)
				pal(4,2)
			end
			self:draw_sprite(40,-15,48,96,79,25)
			if f>35 then
				print_centered("you did it!",x,41,15)
			end
			-- if f>70 then
			-- 	print_centered("you beautiful",x,49)
			-- 	print_centered("person, you!",x,57)
			-- end
			-- print score
			if self.show_score then
				self:draw_score(x,73,"score:",score.."00",format_timer(timer_seconds))
			end
			-- print best
			if self.show_best then
				self:draw_score(x,81,"best:",dget(score_data_index).."00",format_timer(dget(time_data_index)))
			end
			-- show prompt
			if self:draw_prompt("continue") then
				-- show score bang
				if dget(score_data_index)==score then
					print("!",x+9.5,81,9)
				end
				-- show time bang
				if dget(time_data_index)==timer_seconds then
					print("!",x+45.5,81,9)
				end
			end
		end,
		-- update
		function(self)
			if self.frames_alive==115 then
				-- sfx(...)
				score+=max(0,380-timer_seconds)
				self.show_score=true
			elseif self.frames_alive==150 then
				-- sfx(...)
				if score>=dget(score_data_index) then
					dset(score_data_index,score)
				end
				if timer_seconds<=dget(time_data_index) or dget(time_data_index)==0 then
					dset(time_data_index,timer_seconds)
				end
				self.show_best=true
			end
			self:check_for_activation()
		end,
		extends=5, -- entity 5: screen
		frames_until_active=195,
		on_activated=function(self)
			-- entity 7: credit_screen
			slide(spawn_entity(7))
		end,
		draw_score=function(self,x,y,label_text,score_text,time_text)
			print(label_text,x-42.5,y,7)
			print(score_text,x+9.5-4*#score_text,y)
			print(time_text,x+45.5-4*#time_text,y)
			-- draw_sprite(x+18,y,95,16,5,5)
			spr(105,x+18,y)
		end
	},
	-- entity 9: death_screen [sprite data 48-53]
	{
		-- draw
		function(self)
			self:draw_prompt("continue")
		end,
		extends=5, -- entity 5: screen
		frames_until_active=120,
		on_activated=function(self)
			slide(player_health)
			slide(player_figment)
			show_title_screen()
		end
	},
	-- entity 10: player_figment [sprite data 54-59]
	{
		-- draw
		function(self)
			self:draw_sprite(5,6,88,ternary(self.frames_alive<120,8,0),11,8)
		end,
		is_pause_immune=true
	},
	-- entity 11: player [sprite data 60-65]
	{
		-- draw
		function(self)
			if self.invincibility_frames%4<2 or self.stun_frames>0 then
				local facing=self.facing
				local sx,sy,sh,dx,dy,flipped=0,0,8,3+4*facing,6,facing==0
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
				self:draw_sprite(dx,dy,sx,sy,11,sh,flipped)
			end
		end,
		-- update
		function(self)
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
				local col,row,occupant=self:col(),self:row(),get_tile_occupant(self)
				if self.prev_col!=col or self.prev_row!=row then
					-- teeter off the edge of the earth if the player tries to move off the map
					if col!=mid(1,col,8) or row!=mid(1,row,5) then
						self:undo_step()
						self.teeter_frames=11
					end
					-- bump into an obstacle or reflection
					if occupant or (player_reflection and (self.prev_col<5)!=(col<5)) then
						self:bump()
						if occupant then
							occupant:get_bumped()
						end
					end
				end
			end
			return true
		end,
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
		check_inputs=function(self)
			local i
			for i=0,3 do
				if btnp(i) then
					self:queue_step(i)
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
				-- sfx(0,0)
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
			-- entity 28: pain
			spawn_entity(28,self)
			self:get_hurt()
		end,
		get_hurt=function(self)
			if self.invincibility_frames<=0 then
				freeze_and_shake_screen(6,10)
				player_health.anim,player_health.anim_frames,self.invincibility_frames,self.stun_frames,score_mult="lose",20,60,19,1
				if decrement_counter_prop(player_health,"hearts") then
					-- entity 10: player_figment
					promises,is_paused,player_health.render_layer,player_figment={},true,16,spawn_entity(10,player.x+23,player.y+65)
					-- entity 9: death_screen
					spawn_entity(9)
					player_figment:promise_sequence(
						35,
						{"move",63,72,60})
					curtains:set_anim() -- close
					player_health:promise_sequence(
						65,
						{"move",62.5,45,60,ease_in_out,{-60,10,-40,10}})
					player:die()
				end
			end
		end
	},
	-- entity 12: player_health [sprite data 66-71]
	{
		-- draw
		function(self)
			if self.visible then
				local i
				for i=1,4 do
					local sprite=0
					if self.anim=="gain" and i==self.hearts then
						sprite=mid(1,5-flr(self.anim_frames/2),3)
					elseif self.anim=="lose" and i==self.hearts+1 then
						if self.anim_frames>=15 or (self.anim_frames+1)%4<2 then
							sprite=6
						end
					elseif i<=self.hearts then
						sprite=4
					end
					self:draw_sprite(24-8*i,3,9*sprite,30,9,7)
				end
			end
		end,
		-- update
		function(self)
			if decrement_counter_prop(self,"anim_frames") then
				self.anim=nil
			end
		end,
		is_pause_immune=true,
		x=63,
		y=122,
		hearts=4,
		-- anim=nil,
		anim_frames=0
	},
	-- entity 13: boss_health [sprite data 72-77]
	{
		-- draw
		function(self)
			if self.visible then
				rect(33,2,93,8,ternary(self.rainbow_frames>0,rainbow_color,ternary_hard_mode(8,5)))
				rectfill(33,2,mid(33,32+self.health,92),8)
			end
		end,
		-- update
		function(self)
			decrement_counter_prop(self,"rainbow_frames")
			if self.drain_frames>0 then
				self.health-=1
			end
			decrement_counter_prop(self,"drain_frames")
		end,
		-- x=63,
		-- y=5,
		-- visible=false,
		health=0,
		rainbow_frames=0,
		drain_frames=0
	},
	-- entity 14: magic_tile_spawn [sprite data 78-83]
	{
		-- draw
		function(self,x,y,f,f2)
			if f2==10 then
				-- sfx(1,1)
			end
			if f2<=10 then
				f2+=3
				rect(x-f2-1,y-f2,x+f2+1,y+f2,ternary(f<4,5,6))
			end
		end,
		on_death=function(self)
			freeze_and_shake_screen(0,1)
			-- entity 15: magic_tile
			spawn_entity(15,self)
			spawn_particle_burst(self,0,4,16,4)
		end
	},
	-- entity 15: magic_tile [sprite data 84-89]
	{
		-- draw
		function(self)
			pal(7,rainbow_color)
			self:draw_sprite(4,3,55,38,9,7)
		end,
		-- update
		function(self)
			if get_tile_occupant(self) then
				self:die()
				spawn_magic_tile(10)
			end
		end,
		hurtbox_channel=2, -- pickup
		on_hurt=function(self)
			-- sfx(2,1)
			score+=score_mult
			-- entity 29: points
			spawn_entity(29,self.x,self.y-7,{points=score_mult})
			freeze_and_shake_screen(2,2)
			self.hurtbox_channel,self.frames_to_death,score_mult=0,6,min(score_mult+1,8)
			local health_change=ternary(boss_phase==0,12,7)
			local particles=spawn_particle_burst(self,0,ternary(boss_phase>=5,15,25),16,10)
			local i
			for i=1,health_change do
				-- shuffle
				local j=rnd_int(i,#particles)
				local p=particles[j]
				particles[i],particles[j],p.frames_to_death=p,particles[i],300
				-- move towards and fill the boss bar
				p:promise_sequence(
					7+2*i,
					{"move",8+min(boss_health.health+i,60),-58,8,ease_out},
					1,
					"die",
					-- gain health
					function()
						-- sfx(8,1)
						if boss_health.health<60 then
							boss_health.health,boss_health.visible,boss_health.rainbow_frames=mid(0,boss_health.health+1,60),true,15
							local health=boss_health.health
							-- intro stuff
							if boss_phase==0 then
								if health==25 then
									-- entity 22: magic_mirror
									boss=spawn_entity(22)
								elseif health==37 then
									boss.visible=true
								elseif health==60 then
									boss:intro()
								end
							elseif health>=60 then
								-- once the boss is dying, just reset health to 0
								if boss_phase>=5 then
									boss_health.health=0
								-- kill the boss
								elseif boss_phase==4 then
									promises,boss_phase,boss_reflection={},5
									local i
									for i=1,17 do
										spawn_magic_tile(20+13*i)
									end
									boss:promise_sequence(
										"cancel_everything",
										{"reel",60},
										"cancel_everything",
										{"move",40,-20,15,ease_in},
										20,
										function()
											player_reflection:poof()
											player_reflection=player_reflection:die() -- nil
											 -- entity 1: top_hat
											spawn_entity(1,40,-20):poof()
										end,
										"die",
										120,
										{curtains,"set_anim"}, -- close
										100,
										function()
											is_paused=true
											-- entity 8: victory_screen
											spawn_entity(8)
										end)
								-- move to next phase
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
										"decide_next_action")
								end
							end
						end
					end)
			end
			-- on magic tile picked up
			if health_change+boss_health.health<60 and boss_phase<5 then
				spawn_magic_tile(ternary(boss_phase<1,80,120)-min(self.frames_alive,20)) -- 20 frame grace period
			end
		end
	},
	-- entity 16: player_reflection [sprite data 90-95]
	{
		-- draw
		nil,
		-- update
		function(self)
			local prev_col,prev_row=self:col(),self:row()
			self:copy_player()
			if (prev_col!=self:col() or prev_row!=self:row()) and get_tile_occupant(self) then
				get_tile_occupant(self):get_bumped()
				player:bump()
				self:copy_player()
			end
			return true
		end,
		extends=11, -- entity 11: player
		primary_color=11,
		secondary_color=3,
		tertiary_color=3,
		init=function(self)
			self:copy_player()
			self:poof()
		end,
		on_hurt=function(self,entity)
			player:get_hurt(entity)
			self:copy_player()
			-- entity 28: pain
			spawn_entity(28,self)
		end,
		copy_player=function(self)
			self.x,self.facing=80-player.x,({1,0,2,3})[player.facing+1]
			copy_props(player,self,{"y","step_frames","stun_frames","teeter_frames","bump_frames","invincibility_frames","frames_alive"})
		end
	},
	-- entity 17: playing_card [sprite data 96-101]
	{
		-- draw
		function(self)
			-- spin counter-clockwise when moving left
			local sprite=flr(self.frames_alive/4)%4
			if self.vx<0 then
				sprite=(6-sprite)%4
			end
			-- some cards are red
			if self.is_red then
				pal(5,8)
				pal(6,15)
			end
			-- draw the card
			self:draw_sprite(5,7,10*sprite+77,21,10,10)
		end,
		-- vx,is_red
		hitbox_channel=1 -- player
	},
	-- entity 18: flower_patch [sprite data 102-107]
	{
		-- draw
		function(self)
			self:draw_sprite(4,4,ternary(self.hit_frames>0,119,ternary(self.frames_to_death>0,110,101)),71,9,8)
		end,
		-- update
		function(self)
			if decrement_counter_prop(self,"hit_frames") then
				self.hitbox_channel=0
			end
		end,
		hit_frames=0,
		bloom=function(self)
			self.frames_to_death,self.hit_frames,self.hitbox_channel=15,4,1
			local i
			for i=1,2 do
				-- entity 21: particle
				spawn_entity(21,self.x,self.y-2,{
					vx=i-1.5,
					vy=-1-rnd(),
					friction=0.9,
					gravity=0.06,
					frames_to_death=10+rnd(7),
					color=8
				})
			end
		end
	},
	-- entity 19: coin [sprite data 108-113]
	{
		-- draw
		function(self,x,y,f)
			circfill(self.target_x,self.target_y-1,min(flr(f/7),4),2)
			self:draw_sprite(4,5,9*ternary(f>=26,ternary(self.health<3,5,4),ternary(f>10,2,0)+flr(f/3)%2),37,9,9)
		end,
		health=3,
		get_bumped=function(self)
			if decrement_counter_prop(self,"health") then
				self:die()
			end
		end,
		on_death=function(self)
			spawn_particle_burst(self,0,6,6,4)
		end
	},
	-- entity 20: coin_slam [sprite data 114-119]
	{
		-- draw
		function(self)
			-- 0 = left, 1 = right, 2 = up, 3 = down
			self:draw_sprite(5,3,ternary(self.dir>1,47,58),71,11,7,self.dir==0,self.dir==2)
		end,
		-- update
		function(self)
			if self.frames_alive>1 then
				self.hitbox_channel=0
			end
		end,
		hitbox_channel=1 -- player
	},
	-- entity 21: particle [sprite data 120-125]
	{
		-- draw
		function(self,x,y)
			line(x,y,self.prev_x,self.prev_y,ternary(self.color==16,rainbow_color,self.color))
		end,
		-- update
		function(self)
			self.vy+=self.gravity
			self.vx*=self.friction
			self.vy*=self.friction
			self.prev_x,self.prev_y=self.x,self.y
		end,
		friction=1,
		gravity=0,
		-- color=7,
		init=function(self)
			self:update()
			self:apply_velocity()
		end
	},
	-- entity 22: magic_mirror [sprite data 126-131]
	{
		-- draw
		function(self,x,y,f)
			local expression=self.expression
			self:apply_colors()
			if self.visible then
				-- draw mirror
				self:draw_sprite(6,12,115,0,13,30)
			end
			if self.visible or boss_health.rainbow_frames>0 then
				-- the face is rainbowified after the player hits a tile
				if boss_health.rainbow_frames>0 then
					color_wash(rainbow_color)
					if expression>0 and boss_phase>0 then
						pal(13,5)
					end
					expression=8
				end
				-- draw face
				if expression>0 then
					self:draw_sprite(5,7,11*expression-11,57,11,14,false,expression==5 and f%4<2)
				end
			end
			pal()
			self:apply_colors()
			if self.visible then
				-- draw top hat
				if self.is_wearing_top_hat then
					self:draw_sprite(6,15,102,0,13,9)
				end
				-- draw laser preview
				if self.laser_preview_frames%2>0 then
					line(x,y+7,x,60,14)
				end
			end
		end,
		-- update
		function(self)
			local x,y=self.x,self.y
			decrement_counter_prop(self,"laser_charge_frames")
			decrement_counter_prop(self,"laser_preview_frames")
			calc_idle_mult(self,self.frames_alive,2)
			if boss_health.rainbow_frames>12 then
				self.draw_offset_x+=scene_frame%2*2-1
			end
			-- create particles when charging laser
			if self.laser_charge_frames>0 then
				local angle,n=rnd(),ternary_hard_mode(8,18)
				-- entity 21: particle
				spawn_entity(21,x+n*self.vx+22*cos(angle),y+22*sin(angle),{
					color=14,
					frames_to_death=n
				}):move(x+n*self.vx,y,n+2,ease_out)
			end
		end,
		x=40,
		y=-28,
		home_x=40,
		home_y=-28,
		expression=4,
		laser_charge_frames=0,
		laser_preview_frames=0,
		dark_color=14,
		light_color=15,
		idle_mult=0,
		-- visible=false,
		init=function(self)
			local props,y={mirror=self,is_reflection=self.is_reflection,dark_color=self.dark_color,light_color=self.light_color,is_boss_generated=self.is_boss_generated},self.y+5
			-- entity 24: magic_mirror_hand
			self.left_hand=spawn_entity(24,self.x-18,y,props)
			self.coins,self.flowers,props.is_right_hand,props.dir={},{},true,1
			-- entity 24: magic_mirror_hand
			self.right_hand=spawn_entity(24,self.x+18,y,props)
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
				color_wash(self.dark_color)
				pal(8,self.light_color)
				pal(7,self.light_color)
				pal(6,self.light_color)
				pal(2,ternary(self.is_cracked,self.dark_color,self.light_color))
			end
		end,
		-- highest-level commands
		intro=function(self)
			self:promise_sequence(
				"phase_change",
				spawn_magic_tile,
				function()
					scene_frame,player_health.visible=0,true
					boss_phase+=1
				end,
				"decide_next_action")
		end,
		decide_next_action=function(self)
			return self:promise_sequence(
				function()
					if boss_phase==1 then
						if hard_mode then
							return self:promise_sequence(
								"return_to_ready_position",
								"throw_cards",
								"return_to_ready_position",
								"shoot_lasers",
								"return_to_ready_position",
								"despawn_coins",
								"throw_coins")
						else
							return self:promise_sequence(
								"return_to_ready_position",
								{self.left_hand,"throw_cards"},
								{self,"return_to_ready_position"},
								10,
								{self.right_hand,"throw_cards"},
								{self,"return_to_ready_position"},
								25,
								"shoot_lasers")
						end
					elseif boss_phase==2 or boss_phase==3 then
						return self:promise_sequence(
							"return_to_ready_position",
							"conjure_flowers",
							"return_to_ready_position",
							"throw_cards",
							function()
								if hard_mode then
									spawn_reflection(nil,
										"throw_cards",
										13,
										"die")
								end
							end,
							"return_to_ready_position",
							ternary_hard_mode(70,0),
							"shoot_lasers",
							"return_to_ready_position",
							"despawn_coins",
							function()
								if hard_mode then
									spawn_reflection(nil,
										10,
										"throw_hat",
										30,
										"die")
								end
							end,
							"throw_coins")
					elseif boss_phase==4 then
						if hard_mode then
							local n=0
							return self:promise_sequence(
								"return_to_ready_position",
								10)
								:and_then_repeat(5,
									8,
									function()
										spawn_reflection(40-20*n,
											15,
											{"throw_hat",nil,1},
											80-8*n,
											"reform")
										n=(n+1)%5
										if n==0 then
											boss:disappear()
										end
									end)
								:and_then_sequence(
								200)
						else
							return self:promise_sequence(
								function()
									boss_reflection:set_held_state()
								end,
								"set_held_state",
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
							-- throw cards together
								function()
									boss_reflection:promise_sequence(
										84,
										"throw_cards",
										"return_to_ready_position")
								end,
								"throw_cards",
								"return_to_ready_position",
								100,
							-- shoot lasers together
								function()
									boss_reflection:promise_sequence(
										30,
										"shoot_lasers",
										"return_to_ready_position")
								end,
								"shoot_lasers",
								"return_to_ready_position",
								80,
							-- throw coins together
								function()
									boss_reflection:promise_sequence(
										"despawn_coins",
										17,
										{"throw_coins",player_reflection},
										"return_to_ready_position")
								end,
								"despawn_coins",
								"throw_coins",
								"return_to_ready_position",
								100)
						end
					end
				end,
				function()
					-- called this way so that the repeated decide_next_action
					--   calls don't result in an out of memory exception
					self:decide_next_action()
				end)
		end,
		-- appear=function(self)
		-- 	self.visible=true
		-- 	self.left_hand:appear()
		-- 	self.right_hand:appear()
		-- end,
		disappear=function(self)
			self.visible=false
			self.left_hand:disappear()
			self.right_hand:disappear()
		end,
		phase_change=function(self)
			-- music(13)
			local lh,rh=self.left_hand,self.right_hand
			-- todo remove this skip_phase_change_animations schtuff to save 36 tokens
			if skip_phase_change_animations then
				if boss_phase==0 then
					self.is_wearing_top_hat=true
				elseif boss_phase==2 then
					-- entity 16: player_reflection
					player_reflection=spawn_entity(16)
				elseif boss_phase==3 and not hard_mode then
					-- entity 23: magic_mirror_reflection
					boss_reflection=spawn_entity(23)
					self.home_x+=20
				end
			elseif boss_phase==0 then
				return self:promise_sequence(
					50,
					{lh,"appear"},
					30)
				-- shake finger
					:and_then_repeat(2,
						{"set_pose",5},
						6,
						{"set_pose",4},
						6)
					:and_then_sequence(
					4,
				-- grab handle
					{rh,"appear"},
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
				if hard_mode then
					return self:promise_sequence(
						{"return_to_ready_position",2},
						30,
						"set_all_idle",
						10,
					-- pound fists
						"pound",
						"pound",
						"pound",
						function()
							local i
							for i=1,5 do
								-- entity 23: magic_mirror_reflection
								spawn_entity(23):promise_sequence(
									{"move",0,0,40,ease_in_out,{40*cos(i/5),40*sin(i/5),40*cos((i+1)/5),40*sin((i+1)/5)},true},
									2,
									"die")
							end
						end,
						75)
				else
					return self:promise_sequence(
						{"return_to_ready_position",2},
						30,
						"set_all_idle",
						10,
					-- pound fists
						"pound",
						"pound",
						"pound",
					-- the bouquet appears!
						{"set_expression",1},
						function()
							lh.is_holding_bouquet=true
						end,
						{rh,"set_pose"},
						{"move",20,-10,15,ease_in,{-20,-10,-5,0},true},
						35,
					-- sniff the flowers
						{lh,"move",2,-9,20,ease_in,nil,true},
						{self,"set_expression",3},
						30,
						{"set_expression",1},
						15,
					-- they vanish
						function()
							lh:promise_sequence(
								10,
								"set_pose",
								function()
									lh.is_holding_bouquet=false
								end,
								{"move",-22,6,20,ease_in,nil,true})
						end,
						{rh,"move",0,7,20,ease_out_in,{-35,-20,-25,0},true},
						15)
				end
			elseif boss_phase==2 then
				return self:promise_sequence(
					{"return_to_ready_position",2},
					"cast_reflection",
					"return_to_ready_position",
					60)
			elseif boss_phase==3 and not hard_mode then
				return self:promise_sequence(
					{"return_to_ready_position",2},
					{"cast_reflection",true},
					function()
						boss_reflection:return_to_ready_position()
					end,
					"return_to_ready_position")
			end
		end,
		cancel_everything=function(self)
			self.left_hand:cancel_everything()
			self.right_hand:cancel_everything()
			self:cancel_promises()
			self:cancel_move()
			self.laser_charge_frames,self.laser_preview_frames=0,0
			despawn_boss_entities(entities)
		end,
		-- medium-level commands
		pound=function(self)
			self.left_hand:pound()
			return self.right_hand:pound()
		end,
		reel=function(self,times)
			-- entity 26: heart
			spawn_entity(26,10*rnd_int(3,6)-5,4)
			self.is_cracked=boss_phase>=3
			return self:promise_sequence(
				{"set_expression",8},
				"set_all_idle")
				:and_then_repeat(times,
					function()
						self.x,self.y=mid(10,self.x,70),mid(-40,self.y,-20)
						local r,r2=rnd_int(-7,7),rnd_int(-7,7)
						freeze_and_shake_screen(0,3)
						self:poof(2*r2,-2*r)
						self.left_hand:promise_sequence("set_pose","appear",{"move",r,r2,6,ease_out,nil,true})
						self.right_hand:promise_sequence("set_pose","appear",{"move",-r2,r,6,ease_out,nil,true})
						return self:move(-r,r2,6,ease_out,nil,true)
					end)
		end,
		throw_hat=function(self)
			return self:promise_sequence(
				"set_all_idle",
				{self.left_hand,"disappear"},
				{self.right_hand,"move",self.x+5,self.y-6,15,linear},
				{"set_pose",1},
				30,
				"set_pose",
				function()
					self.is_wearing_top_hat=false
					-- entity 2: spinning_top_hat
					spawn_entity(2,self.x,-32,{parent=self})
				end,
				{"move",14,5,3,ease_in,nil,true},
				30)
		end,
		conjure_flowers=function(self)
			-- generate a list of flower locations
			local locations,i={},0
			while i<40 do
				add(locations,{x=i%8*10+5,y=8*flr(i/8)+4})
				i+=rnd_int(1,3)
			end
			-- concentrate
			return self:promise_sequence(
				"set_all_idle",
				function()
					self.left_hand:move_to_temple()
				end,
				{self.right_hand,"move_to_temple"},
				{self,"set_expression",2},
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
								-- entity 18: flower_patch
								add(self.flowers,spawn_entity(18,locations[i]))
							end,
							1)
					end
				end,
				ternary_hard_mode(50,65),
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
			return self:promise_sequence(
				"set_all_idle",
				{"set_expression",2},
				{lh,"move",23,14,20,ease_in,nil,true},
				{"set_pose",1})
			-- wave hand
				:and_then_repeat(2,
					{rh,"move",0,0,40,linear,{18,6,-18,6},true})
				:and_then_sequence(
				function()
					if upgraded_version then
						rh:promise_sequence(
							{"set_pose",1},
							function()
								rh.is_holding_wand=true
							end,
							{"poof",-10})
					end
				end,
			-- poof! the wands appear
				{self,"set_expression",1},
				function()
					lh.is_holding_wand=true
				end,
				{lh,"poof",10},
				30,
			-- raise the wands to cast a spell
				function()
					if upgraded_version then
						rh:flourish_wand()
					end
				end,
				{lh,"flourish_wand"},
				{self,"set_expression",3},
				5,
			-- and finally the spell takes effect
				function()
					if upgraded_version then
						-- entity 23: magic_mirror_reflection
						boss_reflection=spawn_entity(23)
						self.home_x+=20
					else
						-- entity 16: player_reflection
						player_reflection=spawn_entity(16)
					end
				end,
			-- cooldown
				55)
		end,
		throw_cards=function(self,hand)
			self.left_hand:throw_cards()
			return self.right_hand:throw_cards()
		end,
		throw_coins=function(self,target,num_coins)
			target=target or player
			self.left_hand:disappear()
			return self:promise_sequence(
				"set_all_idle",
				{self.right_hand,"move_to_temple"})
				:and_then_repeat((num_coins or 4),
					{self.right_hand,"set_pose",1},
					{self,"set_expression",7},
					ternary_hard_mode(5,15),
					function()
						local target_x,target_y=10*target:col()-5,8*target:row()-4
						-- entity 19: coin
						local coin=spawn_entity(19,self.x+13,self.y-6,{target_x=target_x,target_y=target_y})
						add(self.coins,coin)
						coin:promise_sequence(
							{"move",target_x+2,target_y,25,ease_out,{20,-30,10,-60}},
							2,
							function()
								coin.occupies_tile,coin.hitbox_channel=true,5 -- player, coin
								freeze_and_shake_screen(2,2)
								if hard_mode then
									if target_x>5 then
										-- entity 20: coin_slam
										spawn_entity(20,target_x-10,target_y,{dir=0})
									end
									if target_x<75 then
										-- entity 20: coin_slam
										spawn_entity(20,target_x+10,target_y,{dir=1})
									end
									if target_y>4 then
										-- entity 20: coin_slam
										spawn_entity(20,target_x,target_y-8,{dir=2})
									end
									if target_y<36 then
										-- entity 20: coin_slam
										spawn_entity(20,target_x,target_y+8,{dir=3})
									end
								end
							end,
							{"move",-2,0,8,ease_in_out,{0,-4,0,-4},true},
							function()
								coin.hitbox_channel,coin.hurtbox_channel=1,4 -- player / coin
							end)
					end,
					{self.right_hand,"set_pose",4},
					{self,"set_expression",3},
					ternary(boss_phase>=4,21,20))
		end,
		shoot_lasers=function(self)
			self.left_hand:disappear()
			local col,num_reflections=rnd_int(0,7),2
			return self:promise_sequence(
				{"set_held_state","right"},
				"set_expression",
				"set_all_idle"):and_then_repeat(3,
					function()
						col=(col+rnd_int(2,ternary(hard_mode and boss_phase>1,3,6)))%8
						return self:promise_sequence(
							-- move to a random column
							{"move",10*col+5,-20,ternary_hard_mode(10,15),ease_in,{0,-10,0,-10}},
							1,
							-- charge a laser
							function()
								if boss_phase>1 and not hard_mode then
									local dir=2
									if col>5 or (rnd()<0.5 and col>1) then
										dir=-2
									end
									col+=dir
									self:move(10*dir,0,40,linear,nil,true)
								end
							end,
							"shoot_laser",
							function()
								if hard_mode and boss_phase>1 and num_reflections>0 then
									-- entity 23: magic_mirror_reflection
									local reflection=spawn_entity(23)
									reflection:promise():and_then_repeat(num_reflections,
											10,
											"shoot_laser")
										:and_then(
										"die")
									num_reflections-=1
								end
							end)
					end)
		end,
		shoot_laser=function(self)
			return self:promise_sequence(
					function()
						self.laser_charge_frames=10
					end,
					ternary_hard_mode(9,19),
					"preview_laser",
					-- shoot a laser
					{"set_expression",0},
					function()
						freeze_and_shake_screen(0,4)
						-- entity 25: mirror_laser
						spawn_entity(25,self,nil,{parent=self})
					end,
					16,
					-- cooldown
					"set_expression",
					"preview_laser")
		end,
		preview_laser=function(self)
			self.laser_preview_frames=5
			return 5
		end,
		return_to_ready_position=function(self,expression)--,expression,held_hand)
			local lh,rh,home_x,home_y=self.left_hand,self.right_hand,self.home_x,self.home_y
			lh.is_holding_wand,rh.is_holding_wand=false,false
			-- reset to a default expression/pose
			return self:promise_sequence(
				{lh,"set_pose"},
				{rh,"set_pose"},
				{self,"set_all_idle",true},
				{"set_expression",expression or 1},--expression or 1},
				-- function()
				-- 	if abs(home_x-self.x)>12 or abs(home_y-self.y)>12 then
				-- 		return self:set_held_state(held_hand or "either")
				-- 	end
				-- end,
			-- move to home location
				function()
					self:move(home_x,home_y,15,ease_in)
					lh:move(home_x-18,home_y+5,15,ease_in,{-10,-10,-20,0})
					lh:appear()
					rh:move(home_x+18,home_y+5,15,ease_in,{10,-10,20,0})
					rh:appear()
				end,
				10,
			-- reset state
				"set_held_state")
		end,
		set_held_state=function(self,held_hand)
			local primary,secondary=self.left_hand,self.right_hand
			if held_hand=="right" or (held_hand=="either" and secondary.is_holding_mirror) then
				primary,secondary=secondary,primary
			end
			if secondary.is_holding_mirror then
				secondary:release_mirror()
			end
			if primary.is_holding_mirror then
				if not held_hand then
					primary:release_mirror()
				end
			elseif held_hand then
				primary:grab_mirror_handle()
			end
			return 10
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
	-- entity 23: magic_mirror_reflection [sprite data 132-137]
	{
		-- draw
		nil,
		extends=22, -- entity 22: magic_mirror
		visible=true,
		expression=1,
		is_wearing_top_hat=true,
		home_x=20,
		is_reflection=true,
		init=function(self)
			local color_index=1
			if hard_mode then
				color_index=next_reflection_color
				next_reflection_color=next_reflection_color%5+1
			end
			self.dark_color,self.light_color=({3,8,2,9,12})[color_index],({11,14,13,10,7})[color_index]
			boss.init(self)
			local props={"pose","x","y","visible"}
			copy_props(boss,self,{"x","y","expression"})
			copy_props(boss.left_hand,self.left_hand,props)
			copy_props(boss.right_hand,self.right_hand,props)
		end,
		reform=function(self)
			self:move(boss.x,boss.y,10)
			self.left_hand:move(boss.left_hand.x,boss.left_hand.y,10)
			self.right_hand:move(boss.right_hand.x,boss.right_hand.y,10)
			return self:promise_sequence(10,"die")
		end
	},
	-- entity 24: magic_mirror_hand [sprite data 138-143]
	{
		-- draw
		function(self)
			if self.visible then
				-- hand may be holding a bouquet
				if self.is_holding_bouquet then
					self:draw_sprite(1,12,110,71,9,16)
				end
				-- reflections get a green tone
				if self.is_reflection then
					color_wash(self.dark_color)
					pal(7,self.light_color)
					pal(6,self.light_color)
				end
				-- draw the hand
				local is_right_hand=self.is_right_hand
				self:draw_sprite(ternary(is_right_hand,7,4),8,12*self.pose-12,46,12,11,is_right_hand)
				-- hand may be holding a wand
				if self.is_holding_wand then
					if self.pose==1 then
						self:draw_sprite(ternary(is_right_hand,10,-4),8,91,54,7,13,is_right_hand)
					else
						self:draw_sprite(ternary(is_right_hand,3,2),16,98,54,7,13,is_right_hand)
					end
				end
			end
		end,
		-- update
		function(self)
			local m=self.mirror
			self.render_layer=ternary(self.is_reflection,6,ternary(self.is_right_hand,9,8))
			calc_idle_mult(self,boss.frames_alive+ternary(self.is_right_hand,9,4),4)
			self:apply_velocity()
			if self.is_holding_mirror then
				self.draw_offset_x,self.draw_offset_y,self.x,self.y=m.draw_offset_x,m.draw_offset_y,m.x+2*self.dir,m.y+13
			end
			return true
		end,
		-- is_right_hand,dir
		-- is_holding_bouquet=false,
		pose=3,
		dir=-1,
		idle_mult=0,
		-- highest-level commands
		throw_cards=function(self)
			local is_first=self.is_right_hand!=self.is_reflection
			local dir,promise=self.dir,self:promise_sequence(
				ternary(is_first,0,ternary_hard_mode(13,19)),
				function()
					self.is_idle=false
				end)
			local r
			-- todo reflection should show with left hand first...
			for r=ternary(is_first,0,1),4,2 do
				promise=promise:and_then_sequence(
					-- move to the correct row
					"set_pose",
					{"move",40+52*dir,8*(r%5)+4,18,ease_out_in,{10*dir,-10,10*dir,10}},
					{"set_pose",2},
					ternary_hard_mode(0,12),
					-- throw the card
					{"set_pose",1},
					function()
						-- entity 17: playing_card
						spawn_entity(17,self.x-7*dir,self.y,{
							vx=-1.5*dir,
							is_red=rnd()<0.5
						})
					end,
					10)
			end
			return promise
		end,
		flourish_wand=function(self)
			return self:promise_sequence(
				{"move",40+20*self.dir,-30,12,ease_out,{-20,20,0,20}},
				{"set_pose",6},
				function()
					spawn_particle_burst(self,20,20,3,10)
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
			self.is_holding_wand,self.is_holding_mirror=self:cancel_promises() -- nil,nil
			self:cancel_move()
		end,
		release_mirror=function(self)
			self.is_holding_mirror=false
			return self:promise_sequence(
				"set_pose",
				{"move",15*self.dir,-7,10,ease_in,nil,true})
		end,
		appear=function(self)
			if not self.visible then
				self.visible=true
				return self:poof()
			end
		end,
		disappear=function(self)
			if self.visible then
				self.visible=false
				self:poof()
			end
		end,
		pound=function(self)
			local m,d=self.mirror,20*self.dir
			return self:promise_sequence(
				{"set_pose",2},
				{"move",m.x+4*self.dir,m.y+20,15,ease_out,{d,0,d,0}},
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
	-- entity 25: mirror_laser [sprite data 144-149]
	{
		-- draw
		function(self,x,y)
			pal(14,self.parent.dark_color)
			pal(15,self.parent.light_color)
			sspr(117,30,11,1,x-4.5,y+4.5,11,100)
		end,
		-- update
		function(self)
			self.x=self.parent.x
		end,
		hitbox_channel=1, -- player
		is_hitting=function(self,entity)
			return self:col()==entity:col()
		end
	},
	-- entity 26: heart [sprite data 150-155]
	{
		-- draw
		function(self,x,y,f,f2)
			if f2>30 or f2%4>1 then
				self:draw_sprite(4,5+max(0,f-0.07*f*f),ternary(f2%30<20,36,45),30,9,7)
			end
		end,
		hurtbox_channel=2, -- pickup
		on_hurt=function(self)
			-- gain heart
			if player_health.hearts<4 then
				player_health.hearts+=1
				player_health.anim,player_health.anim_frames="gain",10
			end
			spawn_particle_burst(self,0,6,8,4)
			self:die()
		end
	},
	-- entity 27: poof [sprite data 156-161]
	{
		-- draw
		function(self,x,y,f)
			self:draw_sprite(8,8,64+16*flr(f/3),31,16,14)
		end
	},
	-- entity 28: pain [sprite data 162-167]
	{
		-- draw
		function(self)
			self:draw_sprite(11,16,105,45,23,26)
		end
	},
	-- entity 29: points [sprite data 168-173]
	{
		-- draw
		function(self,x,y)
			print_centered(self.points.."00",x,y,rainbow_color)
		end,
		vy=-0.5
	}
}

-- primary pico-8 functions (_init, _update, _draw)
function _init()
	-- create starting entities
	-- entity 4: curtains
	-- entity 6: title_screen
	title_screen,curtains=spawn_entity(6),spawn_entity(4)
	-- immediately add new entities to the game
	entities={title_screen,curtains}
	-- skip title screen maybe
	if skip_title_screen then
		title_screen.x,title_screen.is_activated,curtains.anim=-200,true,"open"
		title_screen:on_activated()
	end
end

function _update()
	if freeze_frames>0 then
		freeze_frames=decrement_counter(freeze_frames)
		if player then
			player:check_inputs()
		end
	else
		-- update the timer
		if scene_frame%30==0 and not is_paused and boss_phase>0 then
			timer_seconds=min(5999,timer_seconds+1)
		end
		-- increment a bunch of counters
		screen_shake_frames,scene_frame=decrement_counter(screen_shake_frames),increment_counter(scene_frame)
		local num_promises,num_entities=#promises,#entities
		-- calculate rainbow colors
		rainbow_color=flr(scene_frame/4)%6+8
		if rainbow_color==13 then
			rainbow_color=14
		end
		-- update promises
		local i
		for i=1,num_promises do
			if decrement_counter_prop(promises[i],"frames_to_finish") then
				promises[i]:finish()
			end
		end
		filter_out_finished(promises)
		-- update entities
		for i=1,num_entities do
			local entity=entities[i]
			if not is_paused or entity.is_pause_immune then
				-- call the entity's update function
				if not entity:update() then
					entity:apply_velocity()
				end
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
			local i,j
			-- don't use all() or it may cause slowdown
			for i=1,num_entities do
				for j=1,num_entities do
					local entity,entity2=entities[i],entities[j]
					if i!=j and band(entity.hitbox_channel,entity2.hurtbox_channel)>0 and entity:is_hitting(entity2) and entity2.invincibility_frames<=0 then
						entity2:on_hurt(entity)
					end
				end
			end
		end
		-- remove dead entities from the game
		filter_out_finished(entities)
		-- sort entities for rendering
		local i
		for i=1,#entities do
			local j=i
			while j>1 and is_rendered_on_top_of(entities[j-1],entities[j]) do
				entities[j],entities[j-1]=entities[j-1],entities[j]
				j-=1
			end
		end
	end
end

function _draw()
	local shake_x,i,score_text=0,0,score.."00"
	-- clear the screen
	cls()
	-- shake the camera
	if freeze_frames<=0 and screen_shake_frames>0 then
		shake_x=ternary(boss_phase==5,1,-flr(-screen_shake_frames/3))*(scene_frame%2*2-1)
	end
	-- draw the background
	camera(shake_x,-11)
	-- draw stars
	circ(16,39,1,1)
	circ(116,63,1)
	while i<11430 do
		i+=734+i%149
		pset(i%127,flr(i/127))
	end
	-- draw the grid
	camera(shake_x-23,-65)
	draw_sprite(0,-1,47,79,81,49)
	for i=0,39 do
		draw_sprite(10*flr(i/5),i%5*8,83+i%2*11,45,11,9)
	end
	-- draw entities
	foreach(entities,function(entity)
		if entity.render_layer<13 then
			entity:draw2()
		end
	end)
	-- draw the ui
	camera(shake_x)
	if boss_phase>0 then
		-- draw score multiplier
		draw_sprite(6,2,77,10,11,7)
		print(score_mult,8,3,0)
		-- draw score
		print(score_text,121-4*#score_text,3,1)
		-- draw timer
		print(format_timer(timer_seconds),7,120)
	end
	-- draw ui entities
	foreach(entities,function(entity)
		if entity.render_layer>=13 then
			entity:draw2()
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
	-- draw debug info
	-- camera()
	-- print("mem:      "..flr(100*(stat(0)/1024)).."%",2,102,ternary(stat(1)>=819,8,3))
	-- print("cpu:      "..flr(100*stat(1)).."%",2,109,ternary(stat(1)>=0.8,8,3))
	-- print("entities: "..#entities,2,116,ternary(#entities>120,8,3))
	-- print("promises: "..#promises,2,123,ternary(#promises>30,8,3))
end

-- particle functions
function spawn_particle_burst(source,dy,num_particles,color,speed)
	local particles={}
	local i
	for i=1,num_particles do
		local angle,particle_speed=(i+rnd(0.7))/num_particles,speed*(0.5+rnd(0.7))
		-- entity 21: particle
		add(particles,spawn_entity(21,source.x,source.y-dy,{
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

-- magic tile functions
function spawn_magic_tile(frames_to_death)
	if boss_health.health>=60 then
		boss_health.drain_frames=60
	end
	-- entity 14: magic_tile_spawn
	spawn_entity(14,10*rnd_int(1,8)-5,8*rnd_int(1,5)-4,{
		frames_to_death=frames_to_death or 100
	})
end

-- entity functions
function spawn_entity(class_id,x,y,args,skip_init)
	if type(x)=="table" then
		x,y=x.x,x.y
	end
	local k,v,entity
	local the_class,sid=entity_classes[class_id],6*class_id-6
	if the_class.extends then
		entity=spawn_entity(the_class.extends,x,y,args,true)
	else
		-- create default entity
		entity={
			-- lifetime props
			-- finished=false,
			frames_alive=0,
			-- frames_to_death=0,
			-- ordering props
			-- render_layer=5,
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
			update=noop,
			draw=noop,
			draw2=function(self)
				self:draw(self.x,self.y,self.frames_alive,self.frames_to_death)
				pal()
			end,
			draw_offset_x=0,
			draw_offset_y=0,
			draw_sprite=function(self,dx,dy,...)
				draw_sprite(self.x+self.draw_offset_x-dx,self.y+self.draw_offset_y-dy,...)
			end,
			die=function(self)
				if not self.finished then
					self:on_death()
					self.finished=true
				end
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
			cancel_promises=function(self)
				foreach(promises,function(promise)
					if promise.ctx==self then
						promise:cancel()
					end
				end)
			end,
			-- shared methods tacked on here to save tokens
			poof=function(self,dx,dy)
				-- sfx(12,2)
				-- entity 27: poof
				spawn_entity(27,self.x+(dx or 0),self.y+(dy or 0))
				return 12
			end,
			-- move methods
			apply_velocity=function(self)
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
				self.x+=self.vx
				self.y+=self.vy
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
		}
	end
	-- load some properties from the sprite sheet flag data
	entity.render_layer,entity.frames_to_death,entity.is_boss_generated=fget(sid),fget(sid+1),fget(sid+2,0)
	-- add class properties/methods onto it
	for k,v in pairs(the_class) do
		entity[k]=v
	end
	entity.draw,entity.update=the_class[1] or entity.draw,the_class[2] or entity.update
	-- add properties onto it from the arguments
	for k,v in pairs(args or {}) do
		entity[k]=v
	end
	if not skip_init then
		-- initialize it
		entity:init()
		add(entities,entity)
	end
	-- return it
	return entity
end

function despawn_boss_entities(list)
	foreach(list,function(entity)
		if entity.is_boss_generated then
			entity.finished=true
		end
	end)
end

function slide(entity,dir)
	dir=dir or 1
	-- entity.x+=dir*2
	entity:move(-dir*129,0,100,ease_in_out,{dir*70,0,0,0},true)
	return entity
end

function calc_idle_mult(entity,f,n)
	entity.idle_mult=mid(0,entity.idle_mult+ternary(entity.is_idle,0.05,-0.05),1)
	entity.draw_offset_x,entity.draw_offset_y=entity.idle_mult*3*sin(f/60),entity.idle_mult*n*sin(f/30)
end

function copy_props(source,target,props)
	local p
	for p in all(props) do
		target[p]=source[p]
	end
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
		finish=function(self)
			if not self.finished then
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
			-- if the first arg is a table, assume that's the context
			if type(ctx)=="table" then
				promise=make_promise(ctx,...)
			-- otherwise pass on this promise's context
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
		and_then_repeat=function(self,times,...)
			local promise=self
			local i
			for i=1,times do
				promise=promise:and_then_sequence(...)
			end
			return promise
		end
	}
end

function show_title_screen()
	title_screen.x=188
	slide(title_screen):promise_sequence(
		110,
		function()
			starting_phase,title_screen.frames_alive,score_data_index,time_data_index,title_screen.is_activated,hard_mode=1,0,0,1 -- ,false,false
		end)
end

function spawn_reflection(dx,...)
	-- entity 23: magic_mirror_reflection
	local reflection,params=spawn_entity(23),{dx or 20*rnd_dir(),0,15,ease_in,nil,true}
	reflection:move(unpack(params))
	reflection.left_hand:move(unpack(params))
	reflection.right_hand:move(unpack(params))
	reflection:promise_sequence(...)
end

function format_timer(seconds)
	return flr(seconds/60)..ternary(seconds%60<10,":0",":")..seconds%60
end

-- drawing functions
function print_centered(text,x,...)
	print(text,x-2*#text,...)
end

function is_rendered_on_top_of(a,b)
	return ternary(a.render_layer==b.render_layer,a.y>b.y,a.render_layer>b.render_layer)
end

function draw_sprite(x,y,sx,sy,sw,sh,...)
	sspr(sx,sy,sw,sh,x+0.5,y+0.5,sw,sh,...)
end

function color_wash(c)
	local i
	for i=1,15 do
		pal(i,c)
	end
end

-- tile functions
function get_tile_occupant(entity)
	local entity2
	for entity2 in all(entities) do
		if entity2.occupies_tile and entity2:col()==entity:col() and entity2:row()==entity:row() then
			return entity2
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
	return ternary(percent<0.5,ease_out(2*percent),1+ease_in(2*percent-1))/2
end

-- helper functions
function freeze_and_shake_screen(f,s)
	freeze_frames,screen_shake_frames=max(f,freeze_frames),max(s,screen_shake_frames)
end

-- if condition is true return the second argument, otherwise the third
function ternary(condition,if_true,if_false)
	return condition and if_true or if_false
end

function ternary_hard_mode(...)
	return ternary(hard_mode,...)
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

function rnd_dir()
	return 2*rnd_int(0,1)-1
end

-- increment a counter, wrapping to 20000 if it risks overflowing
function increment_counter(n)
	return n+ternary(n>32000,-12000,1)
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

-- filter out anything in list with finished=true
function filter_out_finished(list)
	local num_deleted,k,v=0
	for k,v in pairs(list) do
		if v.finished then
			list[k]=nil
			num_deleted+=1
		else
			list[k-num_deleted],list[k]=v -- ,nil
		end
	end
end


__gfx__
00000ccccc00cc00000000000000cccc000000ccccc0000900cc00000000000000000000ccc000000c000000000000000002220005555555000000000f000000
0000cccccccccccccccc0000000cccccc0000ccccccc0008dccccc000000000000000000ccc000000c0c00000000000000022200055555650000000090f00000
0000cccc1c1cccc1111c1c0000ccc11c10000cccc1c10000cccccc0000c11cccc000000cc1c00000ccccc0000000000000022200055555650000000090f00000
0000cdcc1c1cddd1111c1c00cddcc11c10000dccc1c1000dcc1c1cc0ccc11111cc000ddcc1c00d0ccccccc000000000000022200055555650000009094f09000
0000cccccccccccccccccc000cccccccc0000ccccccc00ddcc1c1cc0ccddcccccc00000cccc000dcccc11c0d000ccccc00022200055555550000094499944900
0000ddcccccddcdddd00000000ddccddc0000ddcccdc000ddccccc0ddccccccdd000000dccc000ccc1c11cd000ccccccc0022200055555550000009977799000
0000ddddddddddd0000000000ddddddd0000dddddddd0000ddcccd0ddddddd000000000dddd00000ccccccc00cc11c11cc022210088888880010097777777900
00000d000d00d00000000000000000d00000000000d000000d0009800000d000000000d000d000dcccccc000dcccccccccd222555555555555509777777777f0
000ccccc00000000c00000000ccccc000000ccccc000000ccccc000000000000000000000000000ddddddd00000ccccc000222055555555555009777777777f0
00ccccccc000000ccc0000000ccccc00000ccccccc0090ccccccc090000000000000000000000000d000d00000ccccccc002005555555555600977777777777f
00ccccccc000000ccc000000ccccccc0000ccccccc000dcccccccd00d0000000d00d0000000d0011111111100dc11c11cd02155511111115561977777777777f
00dcccccd000000ccc000000ccccccc0000dcccccd0080cdddddc080dcccccccd00cdcccccdc01111111111100dcccccd0025511111111111659777777777779
00ccccccc00000ccccc00000dcccccd0000ccccccc0000ddddddd000dcccccccd00ccccccccc01111110101100ccccccc0025551111111115559777777777779
00cdddddc00000dcccd00000dcdddcd0000cdddddc0000ddddddd000cdddddddc00ddddddddd01111111011100dcccccd0025055551115555059777777777779
00ddddddd00000dcccd00000ddddddd0000ddddddd00000ddddd0000ddddddddd0000ddddd0001111110101100ddddddd0020088555555588009777777777779
000d000d000000cdddc00000ddddddd00000000d00000000d00000000ddddddd00000d000d00011111111111000d000d00020055888888855000977777777790
0000000000000ddddddd0000000ddd00000000000000000000000000000000000000000000000011111111102222222222220055555555555000977777777790
0000000000000ddddddd00000000d000000000000000000000000000000000000000000000000222222222222222222222220055555555555000047777777400
00000000000000d000d000000000d0000000000000000000000000000000000000000000000002222222222222222222222200555555555550009949777949f0
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
000000000000000000800000008800000008000000000000000000088000000222222222222220000600000000000000000000600000000000000ef7777777fe
00550550000550550008880888000880880000880880000088800088880588020000000000000000000000000000000000007770000000000000070000000000
05005005005005005008888ee8008888ee8008888ee80008888e00888050ee820000000000000000000077700000000000007770000000000000000007000000
05000005005888885008888ee8008888ee8008888ee80008888e00088808ee820000000000000000000777700000000000070000770000000000000000000007
00500050000588850000888880000888880000888880000888880000800088020000000000000000000777007700000000000000770007770070000000000000
00050500000058500000888880000088800000088800000088800000050880020000077077700000000000007700777000770000000007770000000000000000
00005000000005000008008008008008008000008000000008000000005800020000077777770000007700000000777700770000000070000000000000000000
00000000000000000000000000000dddd00000666660000666d60022222222220000777777770000007770000077077700000000007700000000000000070000
0000000000000000000000000000dddddd000666d77600d66d776027777777770000777777770000007770077770000000007000777700000000000000000000
000000000000dd0000660000000dddddddd0666ddd77666dddd77627111111170007777777777000000000777777000000000000777700000000000007000007
00660000000dddd000666600000dddddddd0666d66676666d6667627177777170007777777777000000000777777000000000070077700777000000000000000
00006600000dddd000006666000dddddddd0666ddd666666ddd66627171117170007777770777000007700077777077077700000000000770000000000000000
000000000000dd0000000066660dddddddd0d666d666dd6d6d6d6d27177777170000777700000000777770000000077077700000000007000000000000000000
0000000000000000000000006600dddddd00dd66666dddd66666dd27111111170000777000000000777770077000077000707077000000000000000000000000
00000000000000000000000000000dddd0000d5ddddd00d5dddd5027777777770000000000000000077000077000000000000000000000000000000000000000
000000000000000000000000000000000000005d5d50000555d50022222222222222222222222222222511111111155111111111500000000000000000000a00
0000000000000000000000000000000000000077000000000000007000000770000000002222222222211555555511115555555110000000000000000000a000
00000000000000000000000000007700000000777000000000000770000007700770000022222222222155111115511551111155100000000000000a0000a000
00000000000000000000000000007700000000077000000000000770000007770770000000676000222151115111511511151115100000000000000a000a0000
0000000000000000000000000770077000000007770000000000077000000077066000000607060022215115151151151155511510000000000000a000aa0000
0000776777770000777000000777067000000000770770000000077000000076777000000607760022215111511151151115111510000a00000000aa0aa00000
00d77777777700d77777700000677067007700776677700000777770770000077770000006000600222155111115511551111155100000a000000aaaaaa00000
00d77dd7600000d77dd7700077066766777707777677000000777677770000076670000000666000222115555555111155555551100000aaa000000aaa0000aa
00d77777777700d777777000777766667760077676770000007676777000000777700000000000002225111111111551111111115000000a00000000aaaaaa00
00d77dd7777700d77dd770000066666666000067677700000066677600000007776d00000000000022222222222550000000000000000000000000000aaa0000
00d67777700000d67777600000006666dd000006666d0000006676600000000066dd000000000000222222222225500000006600000000000000000000a00000
000066660000000066660000000000ddd000000066d00000000dddd000000000ddd0000022222222222222222225550000006600000000000000000000a00000
00006660000000066600000000666000000007770000000076600000000cbb000000006660000000066600002220550000005500000000000000000000000000
006666666000066666660000777772700007777776000067667770000accbbee0000666666600007777727002220000000006600000000000000000000000000
07777772770077766627700ddd772ddd007777766770067677676700aaccbbee80077777dd7700ddd772ddd02220000000005500000000a00000000000000000
0ddd772ddd0077777727700777772777007776677660077676767600aaccbbee800dd77277d70077777277702220055500005500000000a00000000000000000
7777772777777dd772dd7777d77772d7777667766666676766766776aaccbbee887777727777777d77772d77222000550000550000000aaa0000000000000000
77d77772d777776d7d67777d7d772d7d766776666677767677677666aaccbbee887d77772d7767ddd772ddd72220005550005500000aaaaaa00000000a000000
7d7d772d7d7777777727777777722777777666667777677676766776aaccbbee88d7d772d7d7677d77227d7722200006600055000aa0000aaa000000aaa00000
77d77227d777d7d772d7d777ddddddd7766666777776767767777676aaccbbee887d77227d777777727727772220000555005500000000aaaaaa000000a00000
7777277277777d77227d7777ddddddd7766677777667776776767766aaccbbee8877727727777777ddddd7772220000066005500000000aa0aa00000000a0000
77d72777d777777277277777ddddddd776777776677767676767766111ee11cc117772dd7777777ddddddd77222000006600000000000aa000a0000000000000
07ddddddd70077ddddd770077ddddd7700777667777006766676670011ee11cc1007dddd7777007d72777d70009f07770000022220000a000a00000000000000
06772777760077d277d7700667277766007667777770076776767600ddddddddd0067277777600677277776009ff7ff7000002222000a0000a00000000000000
006677766000077277770000666666600007777777000076776670000ddddddd000066777660000666666600fff7f7f0000002222000a0000000000000000000
00006660000000066600000000666000000007770000000076700000000ddd00000000666000000006660000f77f7f0000000222200a00000000000000000000
00006666666066660000660006666666660066666666666000000000000000900900022222222222222222207777777777000000000000088000800000030000
000000660600606000066660666000006660660060600660009999900009000900900222222222222222222777777777777ff880000088888b088e0088030880
000000060600606000060660660000000660600060600060900000009000900900900222222222222222222777077777777ff8188888188883b8888088008880
0000000606006060000000606660000606600600606006600999999900009009009002222222222222222227e777777777770080000080bb3133880008838000
000000060600606000000060060600006600660060600609000000000900900900900222222222222222222077777777777700800800800088833b0330383000
000000060600606000000060006060000000000060600000999999999009000900900222222222222222222fff777f7777770080000080038e8b000008830000
000000060600606000000060000606000000000060600000000000000000009009000222222222222222222ff07700f9777778188888183b888bb00008800300
00000006060060600000006000006060000000006060000222222222222222222222222222222222222222200000000f99777880000088000b30000000000030
00000006060060600000006000000606000000006060000555511111111111111111111111111111111111111111111111111111111111111111111111115555
066000060600606000000060066000606000000060600005000000077770000000500000000000880880000000002222222222222222220003b1330222222225
66660006060060600000006066660006060000006060000177000007f970000000600000000008888ee800000000222222222222222222000333000222222221
66060006060060600000006066060000666000006060000177700077f000000000500000000008888ee800000000222222222222222222000333000222222221
6000000606006060000000606000000006600000606000017797007ff00000000060000000000088888000000000222222222222222222000310000222222221
60000006660060600000006066000000066000006060000177f7707f000000000060000000000008880000000000222222222222222222000130000222222221
0d000dddd0000ddd00000d00ddd00000ddd00000d0d0000177777777000000000060000000000000800000000000222222222222222222000130000222222221
00dddddd000000ddddddd0000ddddddddd00000ddddd000100777777700000000060000000000000000000000000222222222222222222000130000222222221
22222222222222222222222222222222222222222222222100777077700000000050000000000000077000000000222222222222222222222222222222222221
0000666666600000666660000006600066666666666666610077777e700000000053b0ff0777700077f007777000222222222222222222220000d00022222221
000666000006000006666000006666006066600000000661007777770000000000943bff777777707f7077ff7000222222222222222222220000dd0022222221
0066600000006000066666000060660060660000000006610077777770000000004930077777777f7f07f900000022222222222222222222ddddddd022222221
060660000000660006606600000006006066000000006601007777ff7ff0000000990307777777777f7f0000000022222222222222222222dddddddd22222221
060600000000660006606660000006006066000000000661007f77f777f00000009900077777777777770000000022222222222222222222ddddddd022222221
060600000000060006660660000006006066000000000001007ffff7770000000099000777f77777077700000000222222222222222222220000dd0022222221
6066000000000660060606660000060060660000000000010077f777770000000009000f77ff77f777e79949b030222222222222222222220000d00022222221
606600000000066006066066000006006066000000000001007797777700000000000000f777977f777999943b03222222222222222222220000000022222221
60660000000006600600606660000600606600000000000100000000000000000000000000000000009990099999990000000000000000000000000000000001
60660000000006600600660660000600606600000600000100000000000000000000000000099900099909009090099000000099000000000000000000000001
60660000000006600600060666000600606666666600000100000000000000000000090000909900099000909090009900000990900999000000000000000001
60660000000006600600066066000600606600000600000100000000000009999000099000000900909000909090009900009090900990999000000000000001
60660000000006600600006066600600606600000000000100000000000099900900099900000900909000009090099900009090900900099990000000000001
60660000000006600600006606600600606600000000000100000000000099000090090990000900909000009099999000090900900090099009900000000001
60660000000006600600000606660600606600000000000100000000000909000099009099000900909000009099000000090900900900999009990000000001
60660000000006600600000660660600606600000000000100999990000909000099009909900090909099909090900000909000900000909000990099900001
06060000000006000600000060666600606600000000660109990009000909000009009090990090909000909090990000909000900000909009900990099001
06060000000066000600000066066600606600000006600109900009900909000009909009099090909000909090990009099999900009099009009900000901
06066000000066000600000006066600606600000006660199900000900909000009909000909990909000909090099009090009900009090000009900000991
00666000000060000600000006606600606600000000660199900000990909000009900900090990044404404040099090990009900009090000099900000991
000ddd00000d00000dd0000000d0dd00d0ddd00000000d0190900000990909000009900900009440004444004444044040900009900090990000090900090991
0000ddddddd00000dddd000000dddd00dddddddddddddd0190900000990909000000900900000040000000000000044044400009900090900000090900099991
00000000000000000000000000000000000000000000000190900000000909900000900400000000000000000000000004440009900090900000009090009901
00000000000000000000000000000000000000000000000190900000000090900000900040000000000000000000000000000004400909900000009090000001
66666660000000066666000006666666660006666666660190900000000090900000400400000000000000000000000000000044400409000000000909000001
06060006600006666000660066600000666066600000666190900000000009090004000000000000000000000000000000000000004444000099000909000001
06060006600006060000060066000000066066000000066190900000000009404004000000000000000000000000000000000000000444000999900090900001
06060000660006060000060066600006066066600006066109090000009900044440000000000000000000000000000000000000000000009999900090900001
06060000660060600000006006060000660006060000660109090000009900000000000000000000000000000000000000000000000000004990900009090001
06060000660060600000006000606000000000606000000109090000000400000000000000000000000000000000000000000000000000004400000009090001
06060006600060600000006000060600000000060600000100999000000400000000000000000000000000000000000000000000000000000440000009990001
06066666000060600000006000006060000000006060000100099900004000000000000000000000000000000000000000000000000000000044400044900001
06060000600060600000006000000606000000000606000500000944440000000000000000000000000000000000000000000000000000000000044440000005
06060000660060600000006006600060600006600060600555511111111111111111111111111111111111111111111111111111111111111111111111115555
06060000066060600000006066660006060066660006060101010101010101010101010101010101010101010101010101010101010101010101010101010101
06060000066060600000006066060000666066060000666010101010101010101010101010101010101010101010101010101010101010101010101010101010
06060000066006060000060060000000066060000000066000000000000000000000000000000000000000000000000000000000000000000000000000000000
06060000066006060000060066000000066066000000066101010101010101010101010101010101010101010101010101010101010101010101010101010101
0d0d0000dd000dddd000dd00ddd00000ddd0ddd00000ddd000000000000000000000000000000000000000000000000000000000000000000000000000000000
dddddddd0000000ddddd00000ddddddddd000ddddddddd0001000010000100001000010000100001000010000100001000010000100001000010000100001000

__gff__
0500000000000978010000000564000000000e00000000001200000000001200000000001200000000001200000000001200000000001100000000000500000000000d00000000000d0000000000050a000000000300010000000500000000000564010000000400010000000500010000000407000000000b80000000000700
000000000500010000000500000000000a1001000000059600000000090c000000000c03000000000a200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
010400000c13002501135011350124501185000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500
010500002171021721217411f7501e1501c1521a15218152151520963009610217022170200700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700
010c0000215702d5502d5512d5412d5322d5222d5122d5001f5022150009500215020050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000002155500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010500000963009621096110961109601096010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010b0000095110951109111091210c1311213115131182312125121241212512124121251212311e1111811115511002000020000200002000020000200002000020000200002000020000200002000020000200
010a00001525515225152250c205156350c205152250c205152550c2051522515225156350c205152250c205152550c20515225156151561515635152250c20515255156051560515605156350c2051522515205
010c0000092450c2250922009201096350c213092250c203092450c2050c22509225096350c203092250c205092450c20509225096150961509635092250c2030c2400c2130c20315605096350c2050922515205
010c0000092450c2250922009201096350c213092250c203092450c2050c22509225096350c203092250c205092450c20509225096050962509645092250c2030c2400c2130c20315605096350c2050922515205
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011200000922009221102250c21509220092210e2140c2100922009221102250c21509220092210c2140e2100922009221102250c21509220092210e2140c2100922009221102250c21509220092210c2140e210
011200000c2200c22113225102150c2200c22112214102100c2200c22113225102150c2200c2211021412210102201022117225132151c2221c2121c2221c212102201022117225132151c2221c2121c2221c212
011200000c2200c22113225102150c2200c22112214102100c2200c22113225102150c2200c22110214122101022010221232252a2151e2221e2121e2221e2121022010221232252a2151e2221e2121e2221e212
011200000c2200c22113225102150c2200c22112214102100e2200e22115225122150e2200e22112214132100b2200b221122250e2150b2200b221102140e21007220072210e2250b21507220072210b2140c210
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0110000017050170500c0000c00010050100500c0000c000160501605015000150501505015050130501305017050170500c0000c00010050100500c0000c0001605016050150001505015050150501305013050
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010600000c1500c1510c1310c1110c1010c1000c1500c1110c1500c1510c1310c1110c1010c1000c1500c1110c1500c1510c1310c1110c1010c1000c1500c1110c1500c1510c1310c1110c1010c1000c1500c111
01060000131501315113131131110c1010c1001315013111151501515115131151110c1010c1001515015111131501315113131131110c1010c1001315013111151501515115131151110c1010c1001515015111
01060000111501115111131111110c1010c1001115011111111501115111131111110c1010c1001115011111111501115111131111110c1010c1001115011111111501115111131111110c1010c1001115011111
01060000181501815118131181110c1010c10018150181111a1501a1511a1311a1110c1010c1001a1501a111181501815118131181110c1010c10018150181111a1501a1511a1311a1110c1010c1001a1501a111
01060000131501315113131131110c1010c1001315013111131501315113131131110c1010c1001315013111111501115111131111110c1010c1001115011111111501115111131111110c1010c1001115011111
010600001d1501a1511a1311a1110c1010c1001a1501a1111c1501c1511c1311c1110c1010c1001c1501c111181501815118131181110c1010c10018150181111a1501a1511a1311a1110c1010c1001a1501a111
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01100000231502315123142231111c1501c1511c131181002213022151221212115021151211511f1501f131231502315123142231111c1501c1511b1311810022150211301f1301f12021151211411f1501f141
011000002f1502f1512f1422f1112815028151281311c1002e1572d1372b1372d1502d1512d1512b1502b13128150281412811100000000000000000000000002615027152271522815028141281112810000000
011000000415004141041310415007150071410714107131091500914109141091310a1500a1410a1410a1310b1500b1410b1310b150091500914109141091310715007141071410713103150031410314103131
011000000415004150041500415004150041000415004150071500715007150071500715000100071500715009150091500915009150091500010009150091500715007150071500715007150001000315003150
0108002024620186210c611006001863500600186051865524620186210c611006001863500600186051863524620186210c611006001863500600186051863524620186210c6110060018635006001860518635
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
03 10424344
01 12424344
00 13424344
00 14424344
00 13424344
02 15424344
03 17424344
01 191a4344
00 191a4344
00 1b1c4344
00 191a4344
00 1d1e4344
02 191a4344
01 20222444
00 21222444
02 41422444
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344


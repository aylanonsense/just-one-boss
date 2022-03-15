pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
--just one boss
--by ayla~nonsense (formerly bridgs)

--[[
hello there! happy to see you
crack open this cart. my name
is bridgs, and i made this game
in early 2018.

i really wanted to pack a lot
into this game, which meant
doing a ton of token-crunching
and manual code minification.
unfortunately, that makes it a
lot harder for people like you
to come in and have fun hacking
at the game. 'pologies!

to make it up to you, i'm
happy to serve as a resource.
if you have any questions about
the code or the architecture of
this game, feel free to message
me on twitter: @aylanonsense

oh and also... thank you for
playing!

cart data:
	0:	high score
	1:	best time in seconds
	2:	high score (hard mode)
	3:	best time in seconds (hard mode)

sound effects:
	0:	menu music bass
	1:	menu music melody
	2:	menu music melody #2
	3:	menu music melody #3
	7:	extended laser
	8:	tile spawn
	9:	tile collect / game start / score beaten
	10:	tile particle
	11:	poof
	12:	forceful poof / pound
	13:	card throw
	14:	laser
	15:	flower spawn
	16:	flower bloom
	17:	player hurt
	18:	player heal
	19: player teeter
	20:	player bump
	21:	coin flip / coin death
	22:	coin land
	23:	spell cast
	24:	menu advance
	25:	bunny spawn
	26:	hat throw
	28:	bouquet hide
	29:	player step
	30:	reflection spawn
	31:	reflection intro
	32:	drums
	33:	drums #2
	34:	drums #3
	35:	bass walk e
	36:	bass walk e #2
	38:	boss fight melody
	39:	boss fight melody #2
	40:	boss fight melody #3
	41:	intro melody
	42:	intro melody #2
	43:	intro trumpet
	44:	bass walk a
	45:	drum solo
	46:	drum solo #2
	47:	game over melody
	48:	game over drums
	49:	bass walk b -> a
	50:	boss fight melody #4
	51:	boss fight melody #5
	58:	game over melody #2
	59:	restart intro melody
	60:	victory drums #2
	61:	victory harmony
	62:	victory drums
	63:	victory melody

music:
	0-7:	"tutorial"
	8-10:	boss intro
	11-18:	boss fight
	35-36:	game over screen
	37-42:	menu music
	47-48:	victory riff

audio channels:
		music		sfx
		-----		---
	0:	melody		player hurt / player heal
	1:	bass		laser / flower spawn / flower bloom / coin flip / coin death / coin land / spell cast / player step / reflection intro
	2:	percussion	card throw / poof / forceful poof / pound / player bump / bunny spawn / reflection spawn / hat throw
	3:	-			tile spawn / tile collect / tile particle / bouquet reveal / bouquet hide / player teeter

]]

-->8
-- global variable declarations

-- set cart data (for saving and loading high scores)
cartdata("bridgs_justoneboss")

-- useful noop function
function noop() end

-- global debug vars
local starting_phase,skip_phase_change_animations,skip_title_screen,start_on_hard_mode=0,false,false,false

-- global scene vars
local conjure_flowers_counter,next_reflection_color,scene_frame,freeze_frames,screen_shake_frames,timer_seconds,score_data_index,time_data_index,rainbow_color,boss_phase,score,score_mult,promises,entities,title_screen,player,player_health,player_reflection,player_figment,boss,boss_health,boss_reflection,curtains,is_paused,hard_mode=1,1,0,0,0,0,0,1,8,0,0,0,{} -- ,nil,...

-->8
-- entity classes
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
				sfx(25,2) -- bunny spawn
			end
		end
	},
	-- entity 2: spinning_top_hat [sprite data 6-11]
	{
		-- draw
		function(self)
			-- rectfill(10*self:col()-10,8*self:row()-8,10*self:col(),8*self:row(),10)
			color_wash(self.parent.dark_color)
			pal(8,self.parent.light_color)
			pal(1,self.parent.light_color)
			self:draw_sprite(7,10,100,9,15,12)
		end,
		-- update
		function(self)
			self.x+=2*cos(self.frames_alive/50)
		end,
		vy=1
	},
	-- entity 3: bunny [sprite data 12-17]
	{
		-- draw
		function(self)
			self:draw_sprite(7,7,91,45,14,12,self.vx>0)
		end,
		-- update
		function(self)
			self.vy+=0.1
		end
	},
	-- entity 4: curtains [sprite data 18-23]
	--   default_counter = animation
	{
		-- draw
		function(self)
			self:draw_curtain(1,1)
			self:draw_curtain(125,-1)
		end,
		-- update
		function(self)
			self.amount_closed=62*ease_out_in(self.default_counter/100)
			if self.anim!="open" then
				self.amount_closed=62-self.amount_closed
			end
		end,
		is_curtains=true,
		draw_curtain=function(self,x,dir)
			rectfill(x-10*dir,0,x+dir*self.amount_closed,127,0)
			local x2
			for x2=10,63,14 do
				local x3=x+0.5+dir*x2*(1+self.amount_closed/62)/2
				line(x3,11,x3,60+40*cos(x2/90-0.02),2)
			end
		end,
		set_anim=function(self,anim)
			self.anim,self.default_counter=anim,100
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
		check_for_activation=function(self)
			if decrement_counter_prop(self,"frames_until_active") then
				self.is_active=true
			end
			if self.is_active and btnp(1) then
				sfx(24,3) -- menu advance
				self.is_active=slide(self):on_activated() -- false
			end
		end,
		draw_prompt=function(self,text)
			if self.frames_alive%30<22 and self.is_active then
				print_centered("press    to "..text,63,99,13)
				spr(190,63-2*#text,98)
				return true
			end
		end
	},
	-- entity 6: title_screen [sprite data 30-35]
	--   extends entity 5: screen
	{
		-- draw
		function(self)
			self:draw_sprite(23,-29,0,71,47,16)
			self:draw_sprite(23,-47,0,88,47,40)
			-- hard mode prompt
			if self:draw_prompt("start") and dget(0)>0 then
				pal(13,8)
				print_centered("or    for hard mode",63,108)
				-- spr(190,36,107,true)
				spr(190,36,107,1,1,true)
			end
		end,
		-- update
		function(self)
			if self.is_active then
				hard_mode=false
			end
			self:check_for_activation()
			if self.is_active and btnp(0) and dget(0)>0 then
				hard_mode,score_data_index,time_data_index,self.is_active=true,2,3 -- ,false
				slide(self,-1):on_activated()
			end
		end,
		frames_until_active=5,
		on_activated=function()
			music(0) -- "tutorial"
			sfx(9,3) -- game start
			score,timer_seconds,entities=ternary(starting_phase>0,40,0),0,{title_screen,curtains}
			start_game(starting_phase)
		end
	},
	-- entity 7: credit_screen [sprite data 36-41]
	--   extends entity 5: screen
	{
		-- draw
		function(self,x)
			print_centered("thank you for playing!",x+0.5,26,rainbow_color)
			print_centered("created (with love) by bridgs",x+0.5,66,6)
			print("https://brid.gs",x-24.5,75,12)
			print("bridgs_dev",x-24.5,84)
			spr(155,x-35.5,82)
			self:draw_sprite(11,-41,ternary_hard_mode(69,47),79,22,16)
			self:draw_prompt("continue")
		end,
		x=192,
		frames_until_active=130,
		on_activated=function(self)
			show_title_screen()
		end
	},
	-- entity 8: victory_screen [sprite data 42-47]
	--   extends entity 5: screen
	{
		-- draw
		function(self,x,y,f)
			-- congratulations
			self:draw_sprite(39,-15,48,95,79,25)
			if f>=25 then
				print_centered(ternary_hard_mode("you really did it!!","you did it!"),x+0.5,51,15)
			end
			-- print score
			if f>=135 then
				self.draw_score(x,71,"score:",score.."00",format_timer(timer_seconds))
			end
			-- print best
			if f>=170 then
				self.draw_score(x,79,"best:",dget(score_data_index).."00",format_timer(dget(time_data_index)))
			end
			-- show prompt
			if self:draw_prompt("continue") then
				-- show score bang
				if dget(score_data_index)==score then
					print("!",x+9.5,79,9)
				end
				-- show time bang
				if dget(time_data_index)==timer_seconds then
					print("!",x+45.5,79,9)
				end
			end
		end,
		frames_until_active=215,
		on_activated=function(self)
			-- entity 7: credit_screen
			slide(spawn_entity(7))
		end,
		draw_score=function(x,y,label_text,score_text,time_text)
			print(label_text,x-42.5,y,7)
			print(score_text,x+9.5-4*#score_text,y)
			print(time_text,x+45.5-4*#time_text,y)
			spr(173,x+18.5,y)
		end
	},
	-- entity 9: game_over_screen [sprite data 48-53]
	--   extends entity 5: screen
	{
		-- draw
		function(self)
			-- hard mode prompt
			if self:draw_prompt("retry") then
				pal(13,5)
				print_centered("or    to return to menu",63,108)
				-- spr(190,36,107,true)
				spr(190,28,107,1,1,true)
			end
		end,
		-- update
		function(self)
			self:check_for_activation()
			if self.is_active and btnp(0) then
				-- give up
				self.is_active=music(37) -- menu music
				slide(self,-1)
				slide(player_health,-1)
				slide(player_figment,-1)
				show_title_screen(-1)
			end
		end,
		frames_until_active=220,
		on_activated=function(self)
			-- continue
			slide(player_health)
			slide(player_figment)
			score,entities=ternary(boss_phase<=1,40,0),{title_screen,curtains,self,player_health,player_figment}
			self.frames_to_death,player_health.frames_to_death,player_figment.frames_to_death=100,100,100
			if boss_phase<=1 then
				timer_seconds=0
			end
			sfx(9,3) -- game start
			start_game(boss_phase)
		end
	},
	-- entity 10: player_figment [sprite data 54-59]
	{
		-- draw
		function(self)
			self:draw_sprite(5,6,89,ternary(self.frames_alive<190,13,5),11,8)
		end
	},
	-- entity 11: player [sprite data 60-65]
	--   default_counter = bump frames
	{
		-- draw
		function(self)
			if self.invincibility_frames%4<2 or self.stun_frames>0 then
				local facing=self.facing
				local sx,sy,sh,dx,dy,flipped,c=0,0,8,3+4*facing,6,facing==0,ternary(self.teeter_frames%4<2,8,9)
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
				if self.teeter_frames>0 or self.default_counter>0 then
					sx=66
					if self.default_counter<=0 then
						palt(c,true)
						pal(17-c,self.secondary_color)
						sx=44
					end
					if facing>1 then
						dy+=13-5*facing
					else
						dx+=4-facing*8
					end
					if self.teeter_frames<3 and self.default_counter<3 then
						sx=55
					end
				end
				-- getting hurt
				if self.stun_frames>0 then
					sx,sy,sh,dx,dy,flipped=78,11,10,5,8,self.stun_frames%6>2
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
			if self.stun_frames<0 then
				self.render_layer=5
			end
			-- try moving
			self:check_inputs()
			-- apply moves that were delayed from teetering or stun
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
						sfx(19,3) -- player teeter
						self:undo_step()
						self.teeter_frames=11
					end
					-- bump into an obstacle or reflection
					if occupant or (player_reflection and (self.prev_col<5)!=(col<5)) then
						if player_reflection then
							player_reflection:copy_player()
							if get_tile_occupant(player_reflection) then
								get_tile_occupant(player_reflection):get_bumped()
							end
						end
						self:bump()
						if occupant then
							occupant:get_bumped()
						end
						if player_reflection then
							player_reflection:copy_player()
						end
					end
				end
			end
			return true
		end,
		hurtbox_channel=1, -- player
		facing=0, -- 0 = left, 1 = right, 2 = up, 3 = down
		step_frames=0,
		teeter_frames=0,
		stun_frames=0,
		primary_color=12,
		secondary_color=13,
		tertiary_color=0,
		x=45,
		y=20,
		check_inputs=function(self)
			for_each_dir(function(dir)
				if btnp(dir) then
					self:queue_step(dir)
				end
			end)
		end,
		bump=function(self)
			sfx(20,2) -- player bump
			self:undo_step()
			self.default_counter=11
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
			if not self.step_dir and self.teeter_frames<=0 and self.default_counter<=0 and self.stun_frames<=0 then
				if boss_health.health<=0 and boss_phase<=0 and not boss then
					sfx(29,1) -- player step
				end
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
				sfx(17,0) -- player hurt
				self.render_layer=11
				freeze_and_shake_screen(6,10)
				player_health.anim,player_health.default_counter,self.invincibility_frames,self.stun_frames,score_mult="lose",20,60,19,0
				if decrement_counter_prop(player_health,"hearts") then
					-- entity 10: player_figment
					promises,is_paused,player_health.render_layer,player_figment={},true,16,spawn_entity(10,player.x+23,player.y+65)
					music(-1)
					-- entity 9: game_over_screen
					spawn_entity(9)
					player_figment:promise_sequence(
						35,
						{"move",63,72,60})
					curtains:set_anim() -- close
					player_health:promise_sequence(
						35,
						function()
							music(35) -- game over music
						end,
						30,
						{"move",62.5,45,60,linear,{-60,10,-40,10}})
					player:die()
				end
			end
		end
	},
	-- entity 12: player_health [sprite data 66-71]
	--   default_counter = animation frames
	{
		-- draw
		function(self)
			if self.visible then
				local i
				for i=1,4 do
					local sprite=0
					if self.anim=="gain" and i==self.hearts then
						sprite=mid(1,5-flr(self.default_counter/2),3)
					elseif self.anim=="lose" and i==self.hearts+1 then
						if self.default_counter>=15 or (self.default_counter+1)%4<2 then
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
		function(self,counter_reached_zero)
			if counter_reached_zero then
				self.anim=nil
			end
		end,
		x=63,
		y=122,
		hearts=4
		-- anim=nil,
	},
	-- entity 13: boss_health [sprite data 72-77]
	--   default_counter = drain frames
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
			if self.default_counter>0 then
				self.health-=1
			end
		end,
		-- x=63,
		-- y=5,
		-- visible=false,
		health=0,
		rainbow_frames=0
	},
	-- entity 14: magic_tile_spawn [sprite data 78-83]
	{
		-- draw
		function(self,x,y,f,f2)
			if f2==10 then
				sfx(8,3) -- magic tile spawn
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
			freeze_and_shake_screen(2,2)
			self.hurtbox_channel,self.frames_to_death,score_mult=0,6,min(score_mult+1,8)
			sfx(9,3) -- magic tile collect
			score+=score_mult
			-- entity 29: points
			spawn_entity(29,self.x,self.y-7,{points=score_mult})
			local health_change=ternary(boss_phase==0,12,6)
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
						sfx(10,3) -- magic tile particle
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
									music(-1)
									promises,boss_phase,boss_reflection={},5
									local i
									for i=1,10 do
										spawn_magic_tile(20+13*i)
									end
									boss:promise_sequence(
										"cancel_everything",
										"appear",
										{"reel",40},
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
										90,
										function()
											music(47) -- victory music
											is_paused=true
										end,
										75,
										function()
											-- update score
											score+=max(0,380-timer_seconds)
											dset(score_data_index,max(score,dget(score_data_index)))
											if timer_seconds<=dget(time_data_index) or dget(time_data_index)==0 then
												dset(time_data_index,timer_seconds)
											end
											-- entity 8: victory_screen
											spawn_entity(8):promise_sequence(
												135,
												function()
													sfx(24,3) -- menu advance
												end,
												35,
												function()
													sfx(24,3) -- menu advance
												end,
												45,
												function()
													if score>=dget(score_data_index) or timer_seconds<=dget(time_data_index) then
														sfx(9,3) -- score beaten
													end
												end)
										end)
								-- move to next phase
								else
									boss:promise_sequence(
										"cancel_everything",
										"appear",
										{"reel",10},
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
				spawn_magic_tile(ternary(boss_phase<1,100,120)-min(self.frames_alive,20)) -- 20 frame grace period
			end
		end
	},
	-- entity 16: player_reflection [sprite data 90-95]
	--   extends entity 11: player
	{
		-- draw
		nil,
		-- update
		function(self)
			local prev_col,prev_row=self:col(),self:row()
			self:copy_player()
			if (prev_col!=self:col() or prev_row!=self:row()) and get_tile_occupant(self) then
				get_tile_occupant(self):get_bumped()
				if get_tile_occupant(player) then
					get_tile_occupant(player):get_bumped()
				end
				player:bump()
				self:copy_player()
			end
			return true
		end,
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
			copy_props(player,self,{"y","step_frames","stun_frames","teeter_frames","default_counter","invincibility_frames","frames_alive"})
		end
	},
	-- entity 17: playing_card [sprite data 96-101]
	{
		-- draw
		function(self)
			-- spin while moving
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
		end
	},
	-- entity 18: flower_patch [sprite data 102-107]
	--   default_counter = hit frames
	{
		-- draw
		function(self)
			if self.parent.is_reflection and hard_mode then
				pal(8,self.parent.dark_color)
				pal(14,self.parent.light_color)
			end
			self:draw_sprite(4,4,ternary(self.default_counter>0,119,ternary(self.frames_to_death>0,110,101)),71,9,8)
		end,
		-- update
		function(self,counter_reached_zero)
			if counter_reached_zero then
				self.hitbox_channel=0
			end
		end,
		bloom=function(self)
			self.frames_to_death,self.default_counter,self.hitbox_channel=15,4,1
			local i
			for i=1,2 do
				-- entity 21: particle
				spawn_entity(21,self.x,self.y-2,{
					vx=i-1.5,
					vy=-1-rnd(),
					friction=0.9,
					gravity=0.06,
					frames_to_death=10+rnd(7),
					color=ternary(self.parent.is_reflection and hard_mode,self.parent.light_color,8)
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
			sfx(21,1) -- coin death
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
		end
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
	--   default_counter = laser charge frames
	{
		-- draw
		function(self,x,y,f)
			if self.really_visible then
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
						if expression>0 and expression!=5 and boss_phase>0 then
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
					if self.default_counter%2>0 then
						line(x,y+7,x,60,14)
					end
				end
			end
		end,
		-- update
		function(self)
			local x,y=self.x,self.y
			calc_idle_mult(self,self.frames_alive,2)
			if boss_health.rainbow_frames>12 then
				self.draw_offset_x+=scene_frame%2*2-1
			end
		end,
		x=40,
		y=-28,
		really_visible=true,
		home_x=40,
		home_y=-28,
		expression=4,
		dark_color=14,
		light_color=15,
		idle_mult=0,
		-- visible=false,
		init=function(self)
			local props,y={mirror=self,is_reflection=self.is_reflection,dark_color=self.dark_color,light_color=self.light_color,is_boss_generated=self.is_boss_generated},self.y+5
			-- entity 24: magic_mirror_hand
			self.left_hand=spawn_entity(24,self.x-18,y,props)
			self.coins,props.is_right_hand,props.dir={},true,1
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
				local c
				for c in all({8,7,6,2}) do
					pal(c,self.light_color)
				end
			end
		end,
		-- highest-level commands
		intro=function(self)
			music(ternary(boss_phase>=1 or skip_phase_change_animations,25,8)) -- boss fight / boss intro
			self:promise_sequence(
				"phase_change",
				function()
					spawn_magic_tile(130)
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
								10,
								"return_to_ready_position",
								"despawn_coins",
								"throw_coins")
						else
							return self:promise_sequence(
								"return_to_ready_position",
								15,
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
							function()
								if hard_mode then
									spawn_reflection(nil,
										{"conjure_flowers",40},
										"die")
								end
							end,
							15,
							{"conjure_flowers",10},
							30,
							"return_to_ready_position",
							"throw_cards",
							function()
								if hard_mode then
									-- entity 23: magic_mirror_reflection
									local reflection=spawn_entity(23)
									reflection:move(20,0,15,ease_in,nil,true)
									reflection:promise_sequence(
										"throw_cards",
										13,
										"die")
									sfx(30,2) -- reflection spawn
								end
							end,
							"return_to_ready_position",
							ternary_hard_mode(70,0),
							{"shoot_lasers",not hard_mode},
							"return_to_ready_position",
							"despawn_coins",
							function()
								if hard_mode then
									spawn_reflection(ternary(player and player.x<40,20,-20),
										10,
										"throw_hat",
										30,
										"die")
								end
							end,
							"throw_coins",
							"return_to_ready_position")
					elseif boss_phase==4 then
						if hard_mode then
							local n,m=0,0
							return self:promise_sequence(
								-- hat barrage
								"return_to_ready_position",
								10,
								{self.left_hand,"disappear"},
								{self.right_hand,"disappear"})
								:and_then_repeat(5,
									function()
										spawn_reflection(40-20*n,
											8*n,
											{"throw_hat",nil,1},
											32-8*n,
											"reform")
										n=(n+1)%5
									end)
								:and_then_sequence(
								{self,"disappear"},
								145,
								"appear",
								30)
								-- laser barrage
								:and_then_repeat(4,
									10,
									"disappear",
									{"set_expression",5},
									function()
										m=m%4+1
										local col=rnd_int(0,7)
										local i
										for i=1,3 do
											col=(col+2)%8
											spawn_reflection(10*col-35,
												7,
												{"shoot_laser",m==4},
												"reform")
										end
										if m==4 then
											return self:promise_sequence(
												40,
												function()
													spawn_reflection(-50,
														{"set_expression",1},
														"appear",
														25,
														"throw_cards",
														60,
														"reform")
												end,
												177)
										else
											return 66
										end
									end,
									{"set_expression",1},
									"appear")
						else
							return self:promise_sequence(
							-- conjure flowers together
								function()
									boss_reflection:promise_sequence(
										75,
										"conjure_flowers",
										"return_to_ready_position")
								end,
								"conjure_flowers",
								"return_to_ready_position",
								20,
								"conjure_flowers",
								"return_to_ready_position",
							-- throw cards together
								function()
									boss_reflection:promise_sequence(
										84,
										"throw_cards",
										20,
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
								50,
							-- throw coins together
								function()
									boss_reflection:promise_sequence(
										"despawn_coins",
										17,
										{"throw_coins",player_reflection,3},
										"return_to_ready_position")
								end,
								"despawn_coins",
								{"throw_coins",nil,3},
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
		appear=function(self)
			self.really_visible=true
			self.left_hand:appear()
			self.right_hand:appear()
		end,
		disappear=function(self)
			self.really_visible=false
			self.left_hand:disappear()
			self.right_hand:disappear()
		end,
		phase_change=function(self)
			next_reflection_color=1
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
				return self:return_to_ready_position()
			elseif boss_phase==0 then
				return self:promise_sequence(
					66,
					{lh,"appear"},
					20)
				-- shake finger
					:and_then_repeat(2,
						{"set_pose",5},
						3,
						{"set_pose",4},
						3)
					:and_then_sequence(
					20,
				-- grab handle
					{rh,"appear"},
					10,
					{"move",-16,8,10,ease_out,{10,0,10,5},true},
					{"set_pose",2},
				-- show face
					{self,"set_expression"},
					33,
					{"set_expression",6},
					28,
					"set_expression",
					34,
					{"set_expression",1},
					5,
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
					35)
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
									{"move",0,0,40,linear,{40*cos(i/5),40*sin(i/5),40*cos((i+1)/5),40*sin((i+1)/5)},true},
									2,
									"die")
							end
							sfx(31,1) -- reflection intro
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
							sfx(16,3) -- flower bloom
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
									sfx(28,3) -- bouquet hide
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
					"return_to_ready_position",
					60)
			end
		end,
		for_each=function(self,fn,skip_self) -- todo refactor this out unless it's used at least 3 times
			fn(self.left_hand)
			fn(self.right_hand)
			if not skip_self then
				fn(self)
			end
		end,
		cancel_everything=function(self)
			self:for_each(function(entity)
				entity.is_holding_wand=entity:cancel_promises()
				entity:cancel_move()
			end)
			self.default_counter=0
			-- despawn boss entities
			foreach(entities,function(entity)
				if entity.is_boss_generated then
					entity:cancel_promises()
					entity.finished=true
				end
			end)
		end,
		-- medium-level commands
		pound=function(self)
			self.left_hand:pound()
			return self.right_hand:pound()
		end,
		reel=function(self,times)
			-- entity 26: heart
			self:for_each(function(entity)
				entity:appear()
				entity:set_pose()
			end,spawn_entity(26,10*rnd_int(3,6)-5,4))
			self.is_cracked=boss_phase>=3
			return self:promise_sequence(
				{"set_expression",8},
				"set_all_idle")
				:and_then_repeat(times,
					{"for_each",function(entity)
						freeze_and_shake_screen(0,2)
						entity.x,entity.y=mid(10,entity.x,70),mid(-40,entity.y,-20)
						entity:poof(rnd_int(-10,10),rnd_int(-10,10),12)
						entity:move(rnd_int(-7,7),rnd_int(-7,7),6,ease_out,nil,true)
					end},
					5)
		end,
		throw_hat=function(self)
			return self:promise_sequence(
				"set_all_idle",
				{self.left_hand,"disappear"},
				{self.right_hand,"appear"},
				{"move",self.x+5,self.y-6,15,linear},
				{"set_pose",1},
				30,
				"set_pose",
				function()
					sfx(26,2) -- hat throw
					self.is_wearing_top_hat=false
					-- entity 2: spinning_top_hat
					spawn_entity(2,self.x,-32,{parent=self})
				end,
				{"move",14,5,3,ease_in,nil,true},
				{self,30})
		end,
		conjure_flowers=function(self,extra_delay)
			if hard_mode or not self.is_reflection then
				conjure_flowers_counter=1+(conjure_flowers_counter+rnd_int(0,2))%8
			end
			-- generate a list of flower locations
			local flowers={}
			-- concentrate
			self.left_hand:move_to_temple()
			return self:promise_sequence(
				"set_all_idle",
				{self.right_hand,"move_to_temple"},
				{self,"set_expression",2},
			-- spawn the flowers
				function()
					local promise,locations,n,i=self:promise(),{},0
					function do_a_math(m)
						return ternary((n+({1,2,3,5,7,9,10,11})[conjure_flowers_counter])%m>0,1,0)
					end
					for i=0,39 do
						if i==n then
							n+=mid(1,do_a_math(2)+do_a_math(3)+do_a_math(5),3)
							if not self.is_reflection then
								add(locations,{x=i%8*10+5,y=8*flr(i/8)+4})
							end
						elseif self.is_reflection then
							add(locations,{x=i%8*10+5,y=8*flr(i/8)+4})
						end
					end
					for i=1,#locations do
						-- shuffle flowers
						local j=rnd_int(i,#locations)
						locations[i],locations[j],promise=locations[j],locations[i],promise:and_then_sequence(
							1,
							function()
								sfx(15,1) -- flower spawn
								-- entity 18: flower_patch
								add(flowers,spawn_entity(18,locations[i],nil,{parent=self}))
							end)
					end
				end,
				(extra_delay or 0)+ternary_hard_mode(50,65),
			-- bloom the flowers
				function()
					sfx(16,1) -- flower bloom
					local flower
					for flower in all(flowers) do
						flower:bloom()
					end
				end,
				{self.left_hand,"set_pose",5},
				{self.right_hand,"set_pose",5},
				{self,"set_expression",3},
				31)
		end,
		cast_reflection=function(self,upgraded_version)
			local lh,rh,i=self.left_hand,self.right_hand
			-- concentrate
			return self:promise_sequence(
				"set_all_idle",
				{lh,"move",23,14,20,ease_in,nil,true},
				{"set_pose",1})
			-- wave hand
				:and_then_repeat(2,
					{rh,"move",0,0,40,linear,{18,6,-18,6},true})
			-- poof! the wands appear
				:and_then_sequence(
				function()
					if upgraded_version then
						rh:promise_sequence(
							{"set_pose",1},
							function()
								rh.is_holding_wand=true
							end,
							{"poof",-10},
							30,
							"flourish_wand")
					end
				end,
				{self,"set_expression",1},
				function()
					lh.is_holding_wand=true
				end,
				{lh,"poof",10},
				30,
			-- raise the wands to cast a spell
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
			-- self.left_hand:disappear()
			return self:promise_sequence(
				"set_all_idle",
				{self.right_hand,"move_to_temple"})
				:and_then_repeat(num_coins or 4,
					{self,"set_expression",7},
					{self.right_hand,"set_pose",1},
					ternary_hard_mode(7,15),
					function()
						local target_x,target_y=10*target:col()-5,8*target:row()-4
						-- entity 19: coin
						sfx(21,1) -- coin flip
						local coin=spawn_entity(19,self.x+13,self.y-6,{target_x=target_x,target_y=target_y})
						add(self.coins,coin)
						coin:promise_sequence(
							{"move",target_x+2,target_y,25,ease_out,{20,-30,10,-60}},
							2,
							function()
								sfx(22,1) -- coin land
								coin.occupies_tile,coin.hitbox_channel=true,5 -- player, coin
								freeze_and_shake_screen(2,2)
								if hard_mode then
									for_each_dir(function(dir,dx,dy)
										-- entity 20: coin_slam
										spawn_entity(20,mid(5,target_x+10*dx,75),mid(4,target_y+8*dy,36),{dir=dir})
									end)
								end
							end,
							{"move",-2,0,8,linear,{0,-4,0,-4},true},
							function()
								coin.hitbox_channel,coin.hurtbox_channel=1,4 -- player / coin
							end)
					end,
					{"set_pose",4},
					{self,"set_expression",3},
					20)
		end,
		shoot_lasers=function(self,sweep)
			self.left_hand:disappear()
			self.right_hand:disappear()
			local col,num_reflections=rnd_int(0,7),2
			return self:promise_sequence(
				"set_expression",
				"set_all_idle"):and_then_repeat(3,
					function()
						col=(col+rnd_int(2,ternary_hard_mode(3,6)))%8
						return self:promise_sequence(
							-- move to a random column
							{"move",10*col+5,-20,ternary_hard_mode(10,15),ease_in,{0,-10,0,-10}},
							1,
							-- sweep the laser
							function()
								if sweep then
									local dir=2
									if col>5 or (rnd()<0.5 and col>1) then
										dir=-2
									end
									col+=dir
									self:move(10*dir,0,40,linear,nil,true)
								end
							end,
							-- charge + shoot the laser
							"shoot_laser",
							-- spawn a reflection to shoot a laser
							function()
								if hard_mode and boss_phase>1 and num_reflections>0 then
									-- entity 23: magic_mirror_reflection
									spawn_entity(23):promise():and_then_repeat(num_reflections,
											10,
											"shoot_laser")
										:and_then(
										"die")
									num_reflections-=1
								end
							end)
					end)
		end,
		shoot_laser=function(self,long_duration)
			return self:promise_sequence(
					ternary_hard_mode(2,12),
					function()
						sfx(ternary(long_duration,7,14),1) -- laser
						self.default_counter=ternary(long_duration,173,31)
					end,
					12,
					-- shoot a laser
					{"set_expression",0},
					function()
						freeze_and_shake_screen(0,4)
						-- entity 25: mirror_laser
						local laser=spawn_entity(25,self,nil,{parent=self})
						if long_duration then
							laser.frames_to_death=150
						end
					end,
					ternary(long_duration,166,16),
					-- cooldown
					"set_expression",
					5)
		end,
		return_to_ready_position=function(self,expression)--,expression,held_hand)
			local lh,rh,home_x,home_y=self.left_hand,self.right_hand,self.home_x,self.home_y
			lh.is_holding_wand,rh.is_holding_wand=false -- ,false
			-- reset to a default expression/pose
			return self:promise_sequence(
				{lh,"set_pose"},
				{rh,"set_pose"},
				{self,"set_all_idle",true},
				{"set_expression",expression or 1},
			-- move to home location
				function()
					self:move(home_x,home_y,15,ease_in)
					lh:move(home_x-18,home_y+5,15,ease_in,{-10,-10,-20,0})
					lh:appear()
					rh:move(home_x+18,home_y+5,15,ease_in,{10,-10,20,0})
					rh:appear()
				end,
				ternary_hard_mode(15,25))
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
			self:for_each(function(entity)
				entity.is_idle=idle
			end)
		end,
		set_expression=function(self,expression)
			self.expression=expression or 5
		end
	},
	-- entity 23: magic_mirror_reflection [sprite data 132-137]
	--   extends entity 22: magic_mirror
	{
		visible=true,
		expression=1,
		is_wearing_top_hat=true,
		home_x=20,
		is_reflection=true,
		init=function(self)
			local color_index=3
			if hard_mode then
				color_index,next_reflection_color=next_reflection_color,next_reflection_color%5+1
			end
			self.dark_color,self.light_color=({2,1,3,9,8})[color_index],({13,12,11,10,14})[color_index]
			boss.init(self)
			local props={"pose","x","y","visible"}
			copy_props(boss,self,{"x","y","expression"})
			copy_props(boss.left_hand,self.left_hand,props)
			copy_props(boss.right_hand,self.right_hand,props)
		end,
		reform=function(self)
			self:move(boss.x,boss.y,10,ease_out)
			self.left_hand:move(boss.left_hand.x,boss.left_hand.y,10,ease_out)
			self.right_hand:move(boss.right_hand.x,boss.right_hand.y,10,ease_out)
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
						self:draw_sprite(ternary(is_right_hand,10,-4),8,91,57,7,13,is_right_hand)
					else
						self:draw_sprite(ternary(is_right_hand,3,2),16,98,57,7,13,is_right_hand)
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
						sfx(13,2) -- card throw
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
					sfx(23,1) -- spell cast
					spawn_particle_burst(self,20,20,3,10)
					freeze_and_shake_screen(0,20)
				end)
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
					sfx(12,2) -- pound
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
			self.pose=pose or 3
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
		is_hitting=function(self,entity)
			return self:col()==entity:col()
		end
	},
	-- entity 26: heart [sprite data 150-155]
	{
		-- draw
		function(self,x,y,f,f2)
			if f2>30 or f2%4>1 then
				-- self:draw_sprite(4,5+max(0,f-0.07*f*f),ternary(f2%30<20,36,45),30,9,7)
				self:draw_sprite(4,5,36,30,9,7)
			end
		end,
		hurtbox_channel=2, -- pickup
		on_hurt=function(self)
			sfx(18,0) -- player heal
			-- gain heart
			if player_health.hearts<4 then
				player_health.hearts+=1
				player_health.anim,player_health.default_counter="gain",10
			end
			spawn_particle_burst(self,0,6,8,4)
			self:die()
		end
	},
	-- entity 27: poof [sprite data 156-161]
	{
		-- draw
		function(self)
			self:draw_sprite(8,8,64+16*flr(self.frames_alive/3),31,16,14)
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
		function(self)
			print_centered(self.points.."00",self.x+1,self.y,rainbow_color)
		end,
		vy=-0.5
	}
}

-->8
-- main functions
function _init()
	music(37) -- menu music
	-- create starting entities
	-- entity 4: curtains
	-- entity 6: title_screen
	starting_phase,title_screen,curtains=max(starting_phase,ternary(dget(0)>0,1,0)),spawn_entity(6),spawn_entity(4)
	-- immediately add new entities to the game
	entities={title_screen,curtains}
	-- skip title screen maybe
	if skip_title_screen then
		title_screen.x,curtains.anim,title_screen.is_active=-200,"open" -- ,false
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
		-- calculate rainbow colors
		rainbow_color=flr(scene_frame/4)%6+8
		if rainbow_color==13 then
			rainbow_color=14
		end
		-- update promises
		local num_promises=#promises
		local i
		for i=1,num_promises do
			if promises[i] and decrement_counter_prop(promises[i],"frames_to_finish") then
				promises[i]:finish()
			end
		end
		filter_out_finished(promises)
		-- update entities
		local num_entities=#entities
		for i=1,min(#entities,num_entities) do
			local entity=entities[i]
			if entity and (not is_paused or entity.is_pause_immune) then
				-- call the entity's update function
				if not entity:update(decrement_counter_prop(entity,"default_counter")) then
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
			-- don't use all() or it may cause slowdown / also we don't want to update all entities
			for i=1,min(#entities,num_entities) do
				for j=1,min(#entities,num_entities) do
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
		shake_x=ternary(boss_phase==5,1,ceil(screen_shake_frames/3))*(scene_frame%2*2-1)
	end
	-- draw background
	camera(shake_x-1,-1)
	map(0,0,0,0,16,16)
	-- draw entities
	camera(shake_x-23,-65)
	foreach(entities,function(entity)
		if entity.render_layer>=13 then
			camera(shake_x)
		end
		if entity.is_curtains then
			if score_mult>0 then
				-- draw score multiplier
				draw_sprite(6,2,69,71,11,7)
				print(score_mult,8,3,0)
			end
			if timer_seconds>0 then
				-- draw timer
				print(format_timer(timer_seconds),7,120,1)
			end
			if score>0 then
				-- draw score
				print(score_text,121-4*#score_text,3,1)
			end
		end
		entity:draw2()
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

-->8
-- spawn_entity function
function spawn_entity(class_id,x,y,args,skip_init)
	if type(x)=="table" then
		x,y=x.x,x.y
	end
	local k,v,entity
	local the_class,sid=entity_classes[class_id],6*class_id-6
	local extends=fget(sid+3)
	if extends>0 then
		entity=spawn_entity(extends,x,y,args,true)
	else
		-- create default entity
		entity={
			default_counter=0,
			frames_alive=0,
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
			poof=function(self,dx,dy,poof_sound)
				sfx(poof_sound or 11,2) -- forceful poof / poof
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
				return dur-1
			end,
			cancel_move=function(self)
				self.vx,self,vy,self.movement=0,0 -- ,nil
			end
		}
	end
	-- load some properties from the sprite sheet flag data
	entity.render_layer,entity.frames_to_death,entity.is_boss_generated,entity.is_pause_immune,entity.hitbox_channel=fget(sid),fget(sid+1),fget(sid+2,0),fget(sid+2,1),fget(sid+4)
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

-->8
-- helper functions

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
		boss_health.default_counter=61
	end
	-- entity 14: magic_tile_spawn
	spawn_entity(14,10*rnd_int(1,8)-5,8*rnd_int(1,5)-4,{
		frames_to_death=frames_to_death or 100
	})
end

function slide(entity,dir)
	dir=dir or 1
	-- entity.x+=dir*2
	entity:move(-dir*129,0,100,linear,{dir*70,0,0,0},true)
	return entity
end

function calc_idle_mult(entity,f,n)
	entity.idle_mult=mid(0,entity.idle_mult+ternary(entity.is_idle,0.05,-0.05),1)
	entity.draw_offset_x,entity.draw_offset_y=entity.idle_mult*3*sin(f/64),entity.idle_mult*n*sin(f/32)
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

function start_game(phase)
	curtains:promise_sequence(
		ternary(skip_title_screen,0,35),
		{"set_anim","open"},
		function()
			local n=30
			if skip_title_screen then
				curtains.default_counter,n,title_screen.frames_until_active,hard_mode=0,0,0,start_on_hard_mode
			end
			score_mult,boss_phase,is_paused=0,max(0,phase-1) -- ,false
			-- entity 11: player
			-- entity 12: player_health
			-- entity 13: boss_health
			player,player_health,boss_health,player_reflection,player_figment,boss,boss_reflection=spawn_entity(11),spawn_entity(12),spawn_entity(13) -- ,nil,...
			-- hard_mode=true -- todo debug remove
			if phase>0 then
				-- entity 22: magic_mirror
				boss=spawn_entity(22)
				boss.visible,boss_health.visible=true,true
				boss:promise_sequence(n,"intro")
				-- todo remove debug schtuff -> 19 tokens
				boss.is_wearing_top_hat=phase>1
				if phase>3 then
					-- entity 16: player_reflection
					player_reflection=spawn_entity(16)
				end
			else
				spawn_magic_tile(150+n)
			end
		end)
end

function show_title_screen(dir)
	title_screen.x=ternary(dir==-1,-66,192)
	slide(title_screen,dir)
	starting_phase,title_screen.frames_until_active,score_data_index,time_data_index=1,115,0,1
end

function spawn_reflection(dx,...)
	-- entity 23: magic_mirror_reflection
	local reflection,params=spawn_entity(23),{dx or 20*rnd_dir(),0,15,ease_in,nil,true}
	reflection.left_hand:move(unpack(params))
	reflection.right_hand:move(unpack(params))
	reflection:promise_sequence({"move",unpack(params)},1,...)
	sfx(30,2) -- reflection spawn
end

function format_timer(seconds)
	return flr(seconds/60)..ternary(seconds%60<10,":0",":")..seconds%60
end

function for_each_dir(fn)
	-- dir,dx,dy
	fn(0,-1,0) -- left
	fn(1,1,0) -- right
	fn(2,0,-1) -- up
	fn(3,0,1) -- down
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
	local item
	for item in all(list) do
		if item.finished then
			del(list,item)
		end
	end
end

__gfx__
00000ccccc00cc00000000000000cccc000000ccccc0000900cc00000000000000000000ccc0022200000000000000002222220005555555000000000f000000
0000cccccccccccccccc0000000cccccc0000ccccccc0008dccccc000000000000000000ccc00222000000000000000022222200055555650000000090f00000
0000cccc1c1cccc1111c1c0000ccc11c10000cccc1c10000cccccc0000c11cccc000000cc1c00222000000000000000022222200055555650000000090f00000
0000cdcc1c1cddd1111c1c00cddcc11c10000dccc1c1000dcc1c1cc0ccc11111cc000ddcc1c00222000000000000000022222200055555650000009094f09000
0000cccccccccccccccccc000cccccccc0000ccccccc00ddcc1c1cc0ccddcccccc00000cccc00222000000000000000022222200055555550000094499944900
0000ddcccccddcdddd00000000ddccddc0000ddcccdc000ddccccc0ddccccccdd000000dccc00222000000000000000000002200055555550000009977799000
0000ddddddddddd0000000000ddddddd0000dddddddd0000ddcccd0ddddddd000000000dddd00222000000000000000000002210088888880010097777777900
00000d000d00d00000000000000000d00000000000d000000d0009800000d000000000d000d002221111111110000000000022555555555555509777777777f0
000ccccc00000000c00000000ccccc000000ccccc000000ccccc00000000000000000000000002222222222220000000000022055555555555009777777777f0
00ccccccc000000ccc0000000ccccc00000ccccccc0090ccccccc090000000000000000000000222222222222000ccccc000005555555555600977777777777f
00ccccccc000000ccc000000ccccccc0000ccccccc000dcccccccd00d0000000d00d0000000d022222222222200ccccccc00155511111115561977777777777f
00dcccccd000000ccc000000ccccccc0000dcccccd0080cdddddc080dcccccccd00cdcccccdc020000c0000000cc11c11cc05511111111111659777777777779
00ccccccc00000ccccc00000dcccccd0000ccccccc0000ddddddd000dcccccccd00ccccccccc020000c0c0000dcccccccccd5551111111115559777777777779
00cdddddc00000dcccd00000dcdddcd0000cdddddc0000ddddddd000cdddddddc00ddddddddd02000ccccc000000ccccc0005055551115555059777777777779
00ddddddd00000dcccd00000ddddddd0000ddddddd00000ddddd0000ddddddddd0000ddddd0002d0ccccccc0000ccccccc000088555555588009777777777779
000d000d000000cdddc00000ddddddd00000000d00000000d00000000ddddddd00000d000d00020dcccc11c0d0dc11c11cd00055888888855000977777777790
0000000000000ddddddd0000000ddd0000000000000000000000000000000000000000000000020ccc1c11cd000dcccccd000055555555555000977777777790
0000000000000ddddddd00000000d0000000000000000000000000000000000000000000000002000ccccccc000ccccccc000055555555555000047777777400
00000000000000d000d000000000d00000000000000000000000000000000000000000000000020dcccccc00000dcccccd0000555555555550009f49777949f0
00000000000000ccccc0000000000000000000000000000000000000000000000000000000000200ddddddd0000ddddddd000005555555550000944999994490
0000000000000ccccccc0000000c00000000000000000000000000000000000000000000000002000d000d000000d000d0000000055555000000099494949900
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
000000000000000000000000000000000000005d5d50000555d50022222222222222222222222222222222222220009f07770000000000000000000000000a00
0000000000000000000000000000000000000077000000000000007000000770000000002222222222222222222009ff7ff7000000000000000000000000a000
00000000000000000000000000007700000000777000000000000770000007700770000022222222222222222220fff7f7f00000000000000000000a0000a000
00000000000000000000000000007700000000077000000000000770000007770770000011111111222222222220f77f7f000000000000000000000a000a0000
0000000000000000000000000770077000000007770000000000077000000077066000005555555122222222222077777777770000000000000000a000aa0000
0000776777770000777000000777067000000000770770000000077000000076777000005111115522222222222777777777777ff0000a00000000aa0aa00000
00d77777777700d7777770000067706700770077667770000077777077000007777000001115111522222222222777077777777ff00000a000000aaaaaa00000
00d77dd7600000d77dd7700077066766777707777677000000777677770000076670000011555115222222222227e77777777777000000aaa000000aaa0000aa
00d77777777700d777777000777766667760077676770000007676777000000777700000111511152222222222207777777777770000000a00000000aaaaaa00
00d77dd7777700d77dd770000066666666000067677700000066677600000007776d00005111115522222222222fff777f77777700000000000000000aaa0000
00d67777700000d67777600000006666dd000006666d0000006676600000000066dd00005555555122222222222ff07700f97777700000000000000000a00000
000066660000000066660000000000ddd000000066d00000000dddd000000000ddd00000222222222222222222200000000f9977700000000000000000a00000
00006660000000066600000000666000000007770000000076600000000cbb000000006660000000066600002225500000000000000000000000000000000000
006666666000066666660000777772700007777776000067667770000accbb880000666666600007777727002225500000006600000000000000000000000000
07777772770077766627700ddd772ddd007777766770067677676700aaccbb88d0077777dd7700ddd772ddd02225550000006600000000a00000000000000000
0ddd772ddd0077777727700777772777007776677660077676767600aaccbb88d00dd77277d70077777277702220550000005500000000a00000000000000000
7777772777777dd772dd7777d77772d777766776666667676676677daaccbb88dd7777727777777d77772d77222000000000660000000aaa0000000000000000
77d77772d777776d7d67777d7d772d7d76677666667776767767766daaccbb88dd7d77772d7767ddd772ddd72220000000005500000aaaaaa00000000a000000
7d7d772d7d777777772777777772277777766666777767767676677daaccbb88ddd7d772d7d7677d77227d7722200555000055000aa0000aaa000000aaa00000
77d77227d777d7d772d7d777ddddddd776666677777676776777767daaccbb88dd7d77227d777777727727772220005500005500000000aaaaaa000000a00000
7777277277777d77227d7777ddddddd776667777766777677676776daaccbb88dd77727727777777ddddd7772220005550005500000000aa0aa00000000a0000
77d72777d777777277277777ddddddd776777776677767676767766daaccbb88dd7772dd7777777ddddddd77222000066000550000000aa000a0000000000000
07ddddddd70077ddddd770077ddddd77007776677770067666766700118811cc1007dddd7777007d72777d70222000055500550000000a000a00000000000000
06772777760077d277d7700667277766007667777770076776767600118811cc10067277777600677277776022200000660055000000a0000a00000000000000
006677766000077277770000666666600007777777000076776670000666666600006677766000066666660022200000660000000000a0000000000000000000
00006660000000066600000000666000000007770000000076700000000666000000006660000000066600002222222222222222200a00000000000000000000
00006666666066660000660006666666660066666666666000000000000000900900001111111110222222222222222222222000000000088000800000030000
00000066060060600006666066600000666066006060066000999990000900090090011111111111222222220000000022222000000000888b088e0088030880
0000000606006060000606606600000006606000606000609000000090009009009001111110101122222222cc00ccc0222220088888008883b8888088008880
00000006060060600000006066600006066006006060066009999999000090090090011111110111222222220cc0cccc22222088888880bb3133880008838000
00000006060060600000006006060000660066006060060900000000090090090090011111101011222222220cccccc0222220888888800088833b0330383000
0000000606006060000000600060600000000000606000009999999990090009009001111111111122222222c0ccccc022222088888880038e8b000008830000
00000006060060600000006000060600000000006060000000000000000000900900001111111110222222220cccccc0222220088888003b888bb00008800300
000000060600606000000060000060600000000060600002222222222222222222222222222222222222222200cccc0022222000000000000b30000000000030
00000006060060600000006000000606000000006060000000000077770000000500000000000880880000000000000022222222222222000b3bb30222222222
0660000606006060000000600660006060000000606000077000007f970000000100000000008888ee80000000000151111111510067600003b3300200000000
6666000606006060000000606666000606000000606000077700077f000000000100000000008888ee8000000000011155555111060706000333000200cccc00
660600060600606000000060660600006660000060600007797007ff00000000010000000000088888000000000001151111551506077600033000020ccc00c0
6000000606006060000000606000000006600000606000077f7707f000000000010000000000008880000000000001151511151506000600033000020cc000c0
6000000666006060000000606600000006600000606000077777777000000000010000000000000800000000000001155151151500666000033000020cc0c0c0
0d000dddd0000ddd00000d00ddd00000ddd00000d0d000000777777700000000010000000000000000000000000001151511151500000000033000020c00ccc0
00dddddd000000ddddddd0000ddddddddd00000ddddd000007770777000000000100000000000000770000000000011511115515000000000330000200cccc00
222222222222222222222222222222222222222222222220077777e700000000013b0ff0777700077f0077770000011155555111000000002222222200000000
00006666666000006666600000066000666666666666666007777770000000000943bff777777707f7077ff70002222200000111111111110000d00000000000
000666000006000006666000006666006066600000000660077777770000000004930077777777f7f07f90000002222200000110111011110000dd0000010000
00666000000060000666660000606600606600000000066007777ff7ff0000000990307777777777f7f00000000222220000010101010101ddddddd000111000
06066000000066000660660000000600606600000000660007f77f777f000000099000777777777777700000000222220000001000100010dddddddd00010000
06060000000066000660666000000600606600000000066007ffff7770000000099000777f77777077700000000222220000000001010000ddddddd000000000
060600000000060006660660000006006066000000000000077f777770000000009000f77ff77f777e79949b0302222200000010001001000000dd0000000000
60660000000006600606066600000600606600000000000007797777700000000000000f777977f777999943b032222200000000000000000000d00000000000
60660000000006600606606600000600606600000000000200000000000000000000000000000000009990099999990000000000000000000000000000000000
60660000000006600600606660000600606600000000000200000000000000000000000000099900099909009090099000000099000000000000000000000002
60660000000006600600660660000600606600000600000200000000000000000000090000909900099000909090009900000990900999000000000000000002
60660000000006600600060666000600606666666600000200000000000009999000099000000900909000909090009900009090900990999000000000000002
60660000000006600600066066000600606600000600000200000000000099900900099900000900909000009090099900009090900900099990000000000002
60660000000006600600006066600600606600000000000200000000000099000090090990000900909000009099999000090900900090099009900000000002
60660000000006600600006606600600606600000000000200000000000909000099009099000900909000009099000000090900900900999009990000000002
60660000000006600600000606660600606600000000000200999990000909000099009909900090909099909090900000909000900000909000990099900002
60660000000006600600000660660600606600000000000209990009000909000009009090990090909000909090990000909000900000909009900990099002
06060000000006000600000060666600606600000000660209900009900909000009909009099090909000909090990009099999900009099009009900000902
06060000000066000600000066066600606600000006600299900000900909000009909000909990909000909090099009090009900009090000009900000992
06066000000066000600000006066600606600000006660299900000990909000009900900090990044404404040099090990009900009090000099900000992
00666000000060000600000006606600606600000000660290900000990909000009900900009440004444004444044040900009900090990000090900090992
000ddd00000d00000dd0000000d0dd00d0ddd00000000d0290900000990909000000900900000040000000000000044044400009900090900000090900099992
0000ddddddd00000dddd000000dddd00dddddddddddddd0290900000000909900000900400000000000000000000000004440009900090900000009090009902
00000000000000000000000000000000000000000000000290900000000090900000900040000000000000000000000000000004400909900000009090000002
00000000000000000000000000000000000000000000000290900000000090900000400400000000000000000000000000000044400409000000000909000002
66666660000000066666000006666666660006666666660290900000000009090004000000000000000000000000000000000000004444000099000909000002
06060006600006666000660066600000666066600000666290900000000009404004000000000000000000000000000000000000000444000999900090900002
06060006600006060000060066000000066066000000066209090000009900044440000000000000000000000000000000000000000000009999900090900002
06060000660006060000060066600006066066600006066209090000009900000000000000000000000000000000000000000000000000004990900009090002
06060000660060600000006006060000660006060000660209090000000400000000000000000000000000000000000000000000000000004400000009090002
06060000660060600000006000606000000000606000000200999000000400000000000000000000000000000000000000000000000000000440000009990002
06060006600060600000006000060600000000060600000200099900004000000000000000000000000000000000000000000000000000000044400044900002
06066666000060600000006000006060000000006060000200000944440000000000000000000000000000000000000000000000000000000000044440000002
06060000600060600000006000000606000000000606000251111111115111110000000011111151111111511111111151111111115111111111511111111151
06060000660060600000006006600060600006600060600211555555511155550000000055555111555551115555555111555555511155555551115555555111
06060000066060600000006066660006060066660006060215511111551551110000000011115511111155155111115515511111551551111155155111115511
06060000066060600000006066060000666066060000666215111511151511150000000015111511151115151115111515111511151511151115151115111511
06060000066006060000060060000000066060000000066215115151151511550000000051511511555115151151511515115551151511515115151155511511
06060000066006060000060066000000066066000000066215111511151511150000000015111511151115151115111515111511151511151115151115111511
0d0d0000dd000dddd000dd00ddd00000ddd0ddd00000ddd215511111551551110000000011115511111155155111115515511111551551111155155111115511
dddddddd0000000ddddd00000ddddddddd000ddddddddd0211555555511155550000011155555111555551115555555111555555511155555551115555555111
__gff__
0500000000000978010001000564000000000e00020000001200020000001200020500001200020500001200020500001200020500001100020000000500000002000d00020000000d0000000000050a000000000300010000000500000b02000b64010001000400010000000500010000000407000001000b80000000000700
000000000500011600000500000000000a1001000100059600000000090c000000000c03000000000a200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000b000000000b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000bf00000b0000000000000b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000f80a0a0a0a0a0a0a0a0a0a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000abfbfcfdfefafbfcfdfeff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000ab69f6f7feac69f6f7fef900bf0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000babfbfcfdfefafbfcfdfeff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000ab69f6f7feac69f6f7fef9000b0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000abfbfcfdfefafbfcfdfeff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000bcbdbdbdbdbdbdbdbdbdbd00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
01120000071300712107111071200b1300b1210b1110b1200c1300c1210c1110c1200d1300d1210d1110d1200e1300e1210e1110e1200d1300d1210d1110d1200c1300c1210c1110c1200b1300b1210b1110b120
011200001f5301f5211f5110000000000000001f5301f5311f5211f5211f51100000000000000000000000001f5301f5211f5110000000000000001f5301f5311f5211f5211f5113000000000000000000000000
0112000000000000000000026520245302452124521225202453024531245211d5301d5311d5211d5211d5111f5301f5211f5110050000500005001f5301f5311f5211f5211f5113050000500005000000000000
011200001d2301f2211f2211f2211f2221f2221f2221f2211f2110000000000000001a2301a2211a2211a2111d2301f2211f2211f2211f2221f2221f2211f2211f21100000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010b000000200095400c1510d1510f151282612825128261282512826128251282412825128231282412822128231282112822128211282112821128211282112821128211282112821128211000000000000000
010500002173021751217611f7701e1701c1721a17218172151720965009620217022170200700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700
010c0000215702d5502d5512d5412d5322d5222d5001f502215000950021502005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000000
011000002155500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01050000106400e6400c6300763000600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010500001c6601a650186501364007620006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0105000010560105611c5701c57109500095000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500
010b000000200095400c1510d1510f151282612825128261282512826128251231310020000200002000020000200002000000000000000000000000000000000000000000000000000000000000000000000000
010800001775500700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700
01080000287612d7712d7612d7512d741007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000000000000000000000
0107000034630286411c64110631046411c450284511c441284411c43128421000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010400001006010051140601405123060230512807028071280712807128071280612805128041280312802100000000000000000000000000000000000000000000000000000000000000000000000000000000
010700000703013031070211303107021130310702100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010700001304013031070400704107031070310000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010a00002d5502d5312d5210050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000000000000
010e00001556015531000001556015531155210000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010600003462034631346213427132274342143221434224322243422432224342243222434214322140020000200002000020000200002000020000200002000020000200002000020000200002000020000200
010a00002855028531285210000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01060000106401c13122141281512815128151271412613124131201211d121161111111100100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
010a00001f02120021250312b0412e0512f0512e0512d0512b0412803125031210211d02100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010800002d7512d751287412873100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010c00001301000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000001c7301f7511f7521f73100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000001f7601f7711f7721f7721f7721f7621f7421f7511f7311f72100700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000000000000
0108002024610186110c6110060018615006001860518615186101861100611006001861500600186051861524610186110c611006001861500600186051861518610186110c6110060018615006001860518615
0108000024610186110c6110060018615006001860518615186101861100611006001861500600186051861524610186110c61100600186150060018605186151861524625306353c63530640246210c61100000
0108000024610186110c611006001861500600186051861518610186110c6110060018615006001860518615000000060000000000003062024621186110c6113c63030631246210c6113062024621186110c611
011000000413004131041210411107130071210713007121091300913109121091110a1300a1310a1210a1110b1300b1210b1300b121091300912109130091210713007131071210711103130031310312103111
011000000413004131041210411100000000000000000000000000000000000000000000000000000000000004130041310412104111041110000004130041310412104111041110000000000000000000000000
011000000050000500005000050000500005000050000500005000050000500005000050000500005000050000500005000050000000000000000000000000000000000000000000000000000000000000000000
011000002f5302f5212f5212f511285302853128521285002e5302e5212e5212d5302d5212d5212b5302b5212f5302f5212f5212f511285302852128521285002e5302d5202b5302d5302d5212d5212b5302b521
011000002f5302f5212f5212f511285302853128521285002e5302e5212e5212d5302d5252d5352b5302b52128530285212852128511285002850026500265002653027530275212853028521285212851128500
011000001c2301c2211c22118221152311523115221152111b2301b2211b2211a2301a2221a22218230182211c2301c2111c2301c211152201521115220152111b230182201b230182111a2211c2211f23123231
011000002f5302f5212853028521285212851100000000002e5372f5272e5202f5302f5212f5212f5112f5112f5302f52128530285212b530285302b5302e5302d5302d5212b5302853028531285212852128511
01100000265302652128530005000050000500005000050028530285212b53000500005000050000500005002d5302b52028530285212d5302b52028530285212b5302b5212b5402b5312d5402d5312e5402e531
011000000050000000000000050010230102211023010221005000050000500005001f2301f2211f2301f221000000000000000000000000000000000000000000000000001f2301f22121230212212222122221
01100000091300913109121091110c1300c1210c1300c1210e1300e1310e1210e1110f1300f1310f1210f111101301012110130101210f1300f1210f1300f1210e1300e1310e1210e1110c1300c1310c1210c111
0108000018620186210c611246051862500600006003062500503005031860524615306153c6253c62530620246212461100600186150060000600306253c5000050300503306253c5000050300503005033c500
0108000018620186210c611006001862500600006001861500615006150c625186251862524625306253062524620246211861100503306203061100503186253452034511345113451134625005030060030625
011800001c2401c2321c2221c2111c2401c2321c2221c2111c2401c2311c2211a2411524015231152211624017240172321723215221132401323113231132211321112211102401023210232102320e2320e222
01180000186350000000000000001863500000000001863524630186210c6210000000000000000000000000000001864518635186251864518635000000000024630186210c6210000000000000000000000000
011000000b1300b1310b1210b1110e1300e1210e1300e1211013010131101211011111130111311112111111101301012110130101210f1300f1210f1300f1210e1300e1310e1210e1110c1300c1310c1210c111
011000001e2301e22117230172111a2301c2301c2221c2211e2301e22117230172111a2301b2321b2221b221285302852121530215211f5302153021521215211f5301c5201b5301a5301a5311a5311a5211a521
011000002e5302e5212f5302f5312f5312f5212f5212f52123500235002350023500225002250021500235002e5302d5202b5302e5302e5212e5112b5302b5312853028521285212852128511225001b5001c500
011000002823028231282312822128211000002b2202b231282312823228222282110020000200262200020026230222302123021221232302322126230262212823028231282312822128222282122821100000
011000002823028231282312822128211000002b2202b23128231282322822228211002000020026220002002623021231222300000022230212211f2301f2201a2301c2301f230212201f221212202222023220
01100000161701615116141161211516015151151411513113160131511312116170161511614116121151601515115141151311316013151131210e1500e1501015010150000001315013150131501315000000
01140000041600414104121071500916009141091210e1300b1600b1410b1110a150091600914109121071500a1600a1410a1210915007160071410712109150091600914109121091110b1600b1410b1210b111
01100000041600415104141071600916009151091410e16010150101500e160101501315013150131501315000000000000000000000000000000000000000000000000000000000000000000000000000000000
01140000041600415104141071600916009151091410e1600b1600b1510b1410a160091600915109141101601316013151101600e1601316013151101600e1601016010150101401014010130101201012000000
011000000e2220c221102311023110211000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0108000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002b5402b5412b5312b5312d5402d5412d5312d5312e5402e5412e5312e531
01120000186350000018635186300c62100621186350000018635186300c62100621006350c6350c63518635186352463524630186210c621000000000000000000000000000000000000000000000000000b120
011200000e1300e1210b1200912009121091110c1300c121091200612006121061110012002120041200213004130061300713007131071310713107121071210712107111071110711100100001000010000100
010900000461500000046150000004615000001061500000106150000010615000001c615000001c615000001c625000001c625046351c635106351c6351c635286351c635286351c63528645286453464534645
011200001a2301a2111a2301a2211a2111a2301823018211182301822118211182302623026221262112923029230292212b2302b2312b2312b2212b2212b2212b2212b2112b2112b21100000000000000000000
__music__
01 20426044
00 21656144
00 20426044
00 22426244
01 23632044
00 23632044
00 23632044
02 24642044
00 69422044
00 29422044
00 2a2b2044
01 26232044
00 27232044
00 282c2044
00 27232044
00 32312044
00 23632044
00 2d426d44
02 2e426e44
00 35232044
00 35232044
00 41424344
00 41424344
00 41424344
00 41424344
02 3b632044
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
01 2f423044
04 3a424344
01 41004344
00 40004344
00 01004344
00 02004344
00 43004344
02 03004344
00 7f7d7d44
00 41424344
00 41424344
00 41424344
00 3e424344
02 3f3d3c44


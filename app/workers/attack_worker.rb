class AttackWorker
  include Sidekiq::Worker
  sidekiq_options :retry => false

  def perform(player_id, target_id)
    player = User.find(player_id)
    target = User.find(target_id)
    
    # Get current active spaceships of each
    player_ship = player.active_spaceship
    target_ship = target.active_spaceship
    
    # If target is already attacking -> stop
    if player.is_attacking
      player.update_columns(is_attacking: false)
      ActionCable.server.broadcast("player_#{target.id}", method: 'getting_attacked', name: player.full_name)
      ActionCable.server.broadcast("player_#{player.id}", method: 'refresh_target_info')
      return
    end
    
    # Tell target its getting attacked by player
    ActionCable.server.broadcast("player_#{target.id}", method: 'getting_attacked', name: player.full_name)
    
    # Call Police on systems with sec higher than low
    call_police(player)
    
    # Set is attacking to true
    player.update_columns(is_attacking: true)
    
    # While player and target can attack
    while true do
      # Global Cooldown
      sleep(2)
      
      if can_attack(player, target)
        # The attack
        attack = SHIP_VARIABLES[player_ship.name]['power'] * (1.0 - SHIP_VARIABLES[target_ship.name]['defense']/100.0)
        target_ship.update_columns(hp: target_ship.hp - attack.round)
        
        # If target hp is below 0 -> die
        if target_ship.hp <= 0
          target_ship.update_columns(hp: 0)
          target.die and return
        end
        
        # Tell both parties to update their hp and log
        ActionCable.server.broadcast("player_#{target.id}", method: 'update_health', hp: target_ship.hp)
        ActionCable.server.broadcast("player_#{target.id}", method: 'log', text: I18n.t('log.you_got_hit_hp', attacker: player.full_name, hp: attack))
        
        ActionCable.server.broadcast("player_#{player.id}", method: 'update_target_health', hp: target_ship.hp)
        ActionCable.server.broadcast("player_#{player.id}", method: 'log', text: I18n.t('log.you_hit_for_hp', target: target.full_name, hp: attack))
        
        # Tell other users who targeted target to also update hp
        User.where(target_id: target.id).where("online > 0").each do |u|
          ActionCable.server.broadcast("player_#{u.id}", method: 'update_target_health', hp: target_ship.hp)
        end
      else
        return
      end
    end
  end
  
  def can_attack(player, target)
    player = player.reload
    target = target.reload
    
    # Return true if both can be attacked, are in the same location and player has target locked on
    target.can_be_attacked and player.can_be_attacked and target.location == player.location and player.target == target and player.is_attacking
  end
  
  def call_police(player)
    if player.system.security_status != 'low' and Npc.where(npc_type: 'police', target: player.id).empty?
      if player.system.security_status == 'high'
        PoliceWorker.perform_async(player.id, 2)
      else
        PoliceWorker.perform_async(player.id, 10)
      end
    end
  end
end
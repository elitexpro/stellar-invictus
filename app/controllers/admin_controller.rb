class AdminController < ApplicationController
  before_action :check_admin, except: [:mute, :unmute, :delete_chat]
  before_action :check_chat_mod, only: [:mute, :unmute, :delete_chat]
  
  def index
  end
  
  def search
    if params[:name]
      result = User.where("full_name ILIKE ?", "%#{params[:name]}%").where.not(faction_id: nil).first(20)
      render partial: 'admin/search', locals: {users: result} and return
    end
    render json: {}, status: 400
  end
  
  def teleport
    if params[:id]
      user = User.find(params[:id]) rescue nil
      if user and !current_user.in_warp
        ActionCable.server.broadcast("location_#{current_user.location_id}", method: 'player_warp_out', name: current_user.full_name)
        old_system = current_user.system
        current_user.update_columns(location_id: user.location_id, system_id: user.system_id, docked: user.docked, in_warp: false)
        # Tell everyone in old system to update their local players
        old_system.update_local_players
        # Tell everyone in new system to update their local players
        current_user.reload.system.update_local_players
        ActionCable.server.broadcast("location_#{current_user.location_id}", method: 'player_appeared')
        ActionCable.server.broadcast("player_#{current_user.id}", method: 'warp_finish')
        render json: {}, status: 200 and return
      end
    end
    render json: {}, status: 400
  end
  
  def set_credits
    if params[:id] and params[:credits]
      user = User.find(params[:id]) rescue nil
      if user
        user.update_columns(units: params[:credits].to_i)
        ActionCable.server.broadcast("player_#{user.id}", method: 'refresh_player_info')
        render json: {message: I18n.t('admin.successfully_set_credits')}, status: 200 and return
      end
    end
    render json: {}, status: 400
  end
  
  def ban
    if params[:id] and params[:duration] and params[:reason]
      user = User.find(params[:id]) rescue nil
      if user && !user.admin
        if params[:duration].to_i == 0
          user.update_columns(banned: true, banned_until: nil, banreason: params[:reason])
        else
          user.update_columns(banned: true, banned_until: (DateTime.now.to_time + params[:duration].to_i.hours).to_datetime , banreason: params[:reason])
        end
        ActionCable.server.broadcast("player_#{user.id}", method: 'reload_page')
        render json: {message: I18n.t('admin.successfully_banned_user'), banned_until: (user.banned_until.strftime("%F %H:%M") rescue 0)}, status: 200 and return
      end
    end
    render json: {}, status: 400
  end
  
  def unban
    if params[:id]
      user = User.find(params[:id]) rescue nil
      if user and user.banned
        user.update_columns(banned: false, banned_until: nil, banreason: nil)
        render json: {message: I18n.t('admin.successfully_unbanned_user')}, status: 200 and return
      end
    end
    render json: {}, status: 400
  end
  
  def server_message
    if params[:text]
      ActionCable.server.broadcast("appearance", method: 'server_message', text: params[:text])
      render json: {}, status: 200 and return
    end
    render json: {}, status: 400
  end
  
  def mute
    if params[:id]
      user = User.find(params[:id]) rescue nil
      if user and !user.muted
        user.update_columns(muted: true)
        render json: {message: I18n.t('admin.successfully_muted_user')}, status: 200 and return
      end
    end
  end
  
  def unmute
    if params[:id]
      user = User.find(params[:id]) rescue nil
      if user and user.muted
        user.update_columns(muted: false)
        render json: {message: I18n.t('admin.successfully_unmuted_user')}, status: 200 and return
      end
    end
  end
  
  def delete_chat
    if params[:id]
      user = User.find(params[:id]) rescue nil
      if user
        user.chat_messages.destroy_all
        render json: {message: I18n.t('admin.successfully_deleted_chat')}, status: 200 and return
      end
    end
  end
  
end
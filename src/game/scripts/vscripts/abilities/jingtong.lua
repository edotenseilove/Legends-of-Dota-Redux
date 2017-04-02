LinkLuaModifier( "modifier_jingtong", "abilities/jingtong.lua" ,LUA_MODIFIER_MOTION_NONE )

if jingtong ~= "" then jingtong = class({}) end

function jingtong:GetIntrinsicModifierName()
  return "modifier_jingtong"
end

if modifier_jingtong ~= "" then modifier_jingtong = class({}) end

function modifier_jingtong:IsPassive()
  return true
end

function modifier_jingtong:IsHidden()
  return true
end

function modifier_jingtong:IsPurgable()
	return false
end

function modifier_jingtong:DeclareFunctions()
  local funcs = {
    MODIFIER_PROPERTY_COOLDOWN_PERCENTAGE
  }
 
  return funcs
end

function modifier_jingtong:GetPriority()
  return MODIFIER_PRIORITY_ULTRA
end

if IsServer() then
  function modifier_jingtong:GetModifierPercentageCooldown()
    local caster = self:GetParent()

    local core = 0
    if caster:FindItemByName("item_octarine_core") then
      core = 25
    end

    local talent = 0
    if caster:FindAbilityByName("special_bonus_cooldown_reduction_10") and caster:FindAbilityByName("special_bonus_cooldown_reduction_10"):GetLevel() > 0 then
      talent = 10
    elseif caster:FindAbilityByName("special_bonus_cooldown_reduction_12") and caster:FindAbilityByName("special_bonus_cooldown_reduction_12"):GetLevel() > 0 then
      talent = 12
    elseif caster:FindAbilityByName("special_bonus_cooldown_reduction_15") and caster:FindAbilityByName("special_bonus_cooldown_reduction_15"):GetLevel() > 0 then
      talent = 15
    elseif caster:FindAbilityByName("special_bonus_cooldown_reduction_20") and caster:FindAbilityByName("special_bonus_cooldown_reduction_20"):GetLevel() > 0 then
      talent = 20
    elseif caster:FindAbilityByName("special_bonus_cooldown_reduction_25") and caster:FindAbilityByName("special_bonus_cooldown_reduction_25"):GetLevel() > 0 then
      talent = 25
    end

    return self:GetAbility():GetSpecialValueFor("reduce") + core + talent
  end
else
  function modifier_jingtong:GetModifierPercentageCooldown()
    local caster = self:GetParent()

    return self:GetAbility():GetSpecialValueFor("reduce")
  end
end

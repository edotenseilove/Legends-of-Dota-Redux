if spell_lab_symbiotic_modifier == nil then
	spell_lab_symbiotic_modifier = class({})
end

function spell_lab_symbiotic_modifier:OnCreated( kv )
	if IsServer() then
    --self.hHost = kv.target:GetParent()
    self:StartIntervalThink(0.003)
    self.scale = self:GetParent():GetModelScale()
    self:GetParent():SetModelScale(0.001)
	end
end

function spell_lab_symbiotic_modifier:SetHost (hTarget,hMod)
  self.hHost = hTarget
	self.hMod = hMod
end

function spell_lab_symbiotic_modifier:OnDestroy()
	if IsServer() then
	  if self.hMod ~= nil then
	    self.hMod:Destroy()
	  end
    self:GetParent():SetModelScale(self.scale)
		EmitSoundOnLocationWithCaster( self:GetParent():GetOrigin(), "Hero_Bane.Nightmare.End", self:GetParent() )
	end
end

function spell_lab_symbiotic_modifier:DeclareFunctions()
	local funcs = {
    --MODIFIER_PROPERTY_MODEL_CHANGE,
  --  MODIFIER_PROPERTY_MODEL_SCALE,
    MODIFIER_EVENT_ON_SPENT_MANA,
    MODIFIER_EVENT_ON_SET_LOCATION,
		MODIFIER_EVENT_ON_TAKEDAMAGE,
		MODIFIER_EVENT_ON_DEATH,
    MODIFIER_PROPERTY_INVISIBILITY_LEVEL
	}
	return funcs
end

function spell_lab_symbiotic_modifier:IsHidden()
	return false
end

function spell_lab_symbiotic_modifier:GetAttributes()
	return MODIFIER_ATTRIBUTE_IGNORE_INVULNERABLE + MODIFIER_ATTRIBUTE_MULTIPLE + MODIFIER_ATTRIBUTE_PERMANENT
end

function spell_lab_symbiotic_modifier:AllowIllusionDuplicate()
	return false
end

function spell_lab_symbiotic_modifier:CheckState()
	local state = {
	[MODIFIER_STATE_NO_UNIT_COLLISION] = true,
	[MODIFIER_STATE_MAGIC_IMMUNE] = true,
	[MODIFIER_STATE_INVULNERABLE] = true,
  [MODIFIER_STATE_UNSELECTABLE] = true,
  [MODIFIER_STATE_NOT_ON_MINIMAP] = true,
  [MODIFIER_STATE_NO_HEALTH_BAR] = true,
  [MODIFIER_STATE_FROZEN] = true,
  --[MODIFIER_STATE_DISARMED] = true,
  [MODIFIER_STATE_OUT_OF_GAME] = true,
  [MODIFIER_STATE_TRUESIGHT_IMMUNE] = true,
  [MODIFIER_STATE_INVISIBLE] = true
	}
	return state
end

function spell_lab_symbiotic_modifier:OnDeath (kv)
	if IsServer() then
	  if kv.unit ~= self:GetParent() then return end
		self:Destroy()
	end
end

function spell_lab_symbiotic_modifier:OnTakeDamage (kv)
	if IsServer() then
		if kv.unit ~= self.hHost then return end
		if self:GetAbility():GetCooldownTimeRemaining() < 3 then
			self:GetAbility():StartCooldown(3)
		end
	end
end
function spell_lab_symbiotic_modifier:OnSetLocation (kv)
	if IsServer() then
		if kv.unit ~= self:GetParent() then return end
    --DeepPrintTable(kv)
    if self.hHost ~= nil then
      FindClearSpaceForUnit(self.hHost,self:GetParent():GetOrigin(),true)
    end
  end
end
function spell_lab_symbiotic_modifier:OnSpentMana (kv)
	if IsServer() then
		if kv.unit ~= self:GetParent() then return end
    if self.hHost == nil then return end
    local hParent = self:GetParent()
    local mana = (hParent:GetMana() / hParent:GetMaxMana()) * self.hHost:GetMaxMana()
    self.hHost:SetMana(mana);
	end
end

function spell_lab_symbiotic_modifier:Terminate (attacker)
  if attacker then
    self:GetParent():Kill(self:GetAbility(),attacker)
  end
  self:Destroy()
end

function spell_lab_symbiotic_modifier:OnIntervalThink()
	if IsServer() then
    if self.hHost == nil then return end
    local hParent = self:GetParent()
    local mana = (self.hHost:GetMana() / self.hHost:GetMaxMana()) * hParent:GetMaxMana()
    hParent:SetMana(mana)
    local pos = self.hHost:GetAbsOrigin()
    local up = Vector(0,0,300)
    hParent:SetAbsOrigin(pos+up)
	end
end

--function spell_lab_symbiotic_modifier:GetModifierModelChange() return "models/items/bane/slumbering_terror/slumbering_terror_nightmare_model.vmdl" end
function spell_lab_symbiotic_modifier:GetModifierInvisibilityLevel()
  return 1
end

--koei edited
local M = {}

function M.shoot(api)
    api:setShotDamageMultiplier(1 + (api:getChargeProgress() / 2))
    api:shootOnce(api:isShootingNeedConsumeAmmo())
end

return M
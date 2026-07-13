local M = {}

function M.shoot(api)
    if (api:getAimingProgress() >= 0.9) then
        api:shootOnce(api:isShootingNeedConsumeAmmo())
    end
end

return M
import os
import re
from gopherbot_v2 import Robot

import os
import re
from gopherbot_v2 import Robot

class AccessVerifier:
    DEVOPS_USER = "david"

    @classmethod
    def verify_allowed_access(cls, bot, action_description):
        requesting_user = os.getenv('GOPHER_USER', 'unknown user')
        if requesting_user == cls.DEVOPS_USER:
            return True

        # Prompt to check if DevOps is ready for approval
        ready_check = bot.PromptForReply("YesNo", "This request requires approval; is DevOps ready to approve the request? (y/n)")
        if ready_check.ret != Robot.Ok or re.match(r"n.*", ready_check.__str__(), flags=re.IGNORECASE):
            bot.Say("Please arrange a short meeting with DevOps to complete this request later")
            return False

        bot.Say("Hang tight while I reach out to DevOps to approve this action...")
        message = f"User {requesting_user} is requesting \"{action_description}\", approve? (y/n)"
        
        # Prompt DevOps for approval
        rep = bot.PromptUserChannelThreadForReply("YesNo", cls.DEVOPS_USER, "", "", message)

        if rep.ret != Robot.Ok:
            bot.Say("Eh, sorry bub, I'm having trouble hearing you - try typing faster?")
            return False
        else:
            reply = rep.__str__()
            if re.match(r"y.*", reply, flags=re.IGNORECASE):
                bot.Say("Approved")
                return True
            else:
                bot.Say("Action denied")
                return False

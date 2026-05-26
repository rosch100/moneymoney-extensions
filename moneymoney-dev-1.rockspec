package = "MoneyMoney"
version = "dev-1"
source = {
   url = "*** please add URL for source tarball, zip or repository here ***"
}
description = {
   homepage = "*** please enter a project homepage ***",
   license = "*** please specify a license ***"
}
dependencies = {
   "lua >= 5.1, < 5.5"
}
build = {
   type = "builtin",
   modules = {
      ["Bank of America"] = "extensions/Bank of America.lua",
      Fidelity = "extensions/Fidelity.lua",
      ["Presidential Bank"] = "extensions/Presidential Bank.lua",
      Shareview = "extensions/Shareview.lua"
   }
}

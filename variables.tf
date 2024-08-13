#обьявление переменной access со значениеями token zone
variable access{
   type= map (any)
   default = {
     token = ""
     cloud_id = "b1gbhabnd2jbsnp8akhk"
     folder_id = "b1g0khs670dnper1liqf"
     zone = "ru-central1-b"

   }
}
variable "data" {
  type = map(any)
  default = {
  count = 3
  account=  "alex"
  }
}

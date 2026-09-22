t1 = time()
sleep(10)
t2 = time()
if t2 >= t1 {
  print("time_ok")
} else {
  print("time_fail")
}

r1 = random(10, 20)
if r1 >= 10 && r1 <= 20 {
  print("rand_ok")
} else {
  print("rand_fail")
}

r2 = random(100)
if r2 >= 0 && r2 < 100 {
  print("rand_ok")
} else {
  print("rand_fail")
}

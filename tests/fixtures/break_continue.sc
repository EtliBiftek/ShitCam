i = 0
while i < 10 {
  if i == 5 {
    break
  }
  i = i + 1
}
print(i)

j = 0
sum = 0
while j < 10 {
  j = j + 1
  if j % 2 == 0 {
    continue
  }
  sum = sum + j
}
print(sum)

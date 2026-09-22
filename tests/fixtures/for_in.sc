nums = [10, 20, 30, 40, 50]
sum = 0
for n in nums {
    if n == 40 {
        break
    }
    if n == 20 {
        continue
    }
    sum += n
}
print(sum)

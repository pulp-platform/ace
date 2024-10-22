from random import randrange

def gen_rand_mem(
  file="main_mem.mem",
  addr_space=32,
  ):

  final_addr = 2**addr_space
  with open(file, "w") as mem_file:
    for _ in range(0, final_addr // 4):
      rand_vals = 4*[""]
      for j in range(0, 4):
        rand_vals[j] = randrange(2**8)
      mem_file.write("{:2x} {:2x} {:2x} {:2x}\n".format(
        rand_vals[0], rand_vals[1], rand_vals[2], rand_vals[3]
      ))

if __name__ == "__main__":
  import argparse
  parser = argparse.ArgumentParser(
    description=('Script to write data to a file'
                 'based on address space.')
  )
  parser.add_argument(
    'file',
    type=str,
    help='The filename where data will be written'
  )
  parser.add_argument(
    'addr_space',
    type=int,
    help='The amount of data (in bytes) that will be written'
  )
  args = vars(parser.parse_args())
  gen_rand_mem(**args)

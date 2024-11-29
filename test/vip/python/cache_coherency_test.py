from cache_state import \
  CacheState, CachelineState, \
  CachelineStateEnum, CacheSetFullException, \
  StateBits
from math import log2
from typing import List
from memory_state import MemoryState
from common import MemoryRange
from transactions import \
  CacheTransactionSequence, CacheTransaction, CacheReqOp
from random import random, randint, choice, sample
import os
import logging
import pdb
logger = logging.getLogger(__name__)


class CoherencyError(AssertionError):
  pass


class CacheCoherencyTest:
  def __init__(
      self,
      addr_width: int,
      data_width: int,
      word_width: int,
      cacheline_words: int,
      ways: int,
      sets: int,
      n_caches: int,
      n_transactions: int,
      target_dir: str,
      check: bool,
      debug: bool,
      **kwargs
      ):

    logging.basicConfig(filename='cache_python.log', filemode='w', level=logging.INFO)

    self.aw = addr_width
    self.dw = data_width
    self.word_width = word_width
    self.cacheline_words = cacheline_words
    self.ways = ways
    self.sets = sets
    self.n_caches = n_caches
    self.n_transactions = n_transactions
    self.target_dir = target_dir
    self.check = check
    self.debug = debug

    self.cacheline_bytes = \
      self.cacheline_words * self.word_width // 8

    self.mem_ranges : list[MemoryRange] = []

  @property
  def caches(self) -> List[CacheState]:
    if not hasattr(self, '_caches'):
      self._caches = []
      for _ in range(0, self.n_caches):
        cache = CacheState(
            addr_width=self.aw,
            data_width=self.dw,
            word_width=self.word_width,
            cacheline_words=self.cacheline_words,
            ways=self.ways,
            sets=self.sets
          )
        cache.init_cache()
        self._caches.append(cache)
    return self._caches
  @caches.setter
  def caches(self, caches: List[CacheState]):
    self._caches = caches

  @property
  def mem_state(self) -> MemoryState:
    if not hasattr(self, '_mem_state'):
      if not self.mem_ranges:
        raise Exception("Define self.mem_ranges!")
      self._mem_state = MemoryState(self.mem_ranges)
    return self._mem_state
  @mem_state.setter
  def mem_state(self, mem_state: MemoryState):
    self._mem_state = mem_state

  @property
  def transactions(self) -> List[CacheTransactionSequence]:
    if not hasattr(self, '_transactions'):
      if not self.mem_ranges:
        raise Exception("Define self.mem_ranges!")
      self._transactions = []
      for _ in range(self.n_caches):
        self._transactions.append(
          CacheTransactionSequence(
          self.aw, self.dw, self.mem_ranges
          )
        )
    return self._transactions
  @transactions.setter
  def transactions(self, txns: List[CacheTransactionSequence]):
    self._transactions = txns

  def add_memory_range(self, memory_range: MemoryRange):
    self.mem_ranges.append(memory_range)

  def set_cache_line(
      self,
      n_cache: int,
      addr: int,
      data: List[int],
      state: List[bool]
    ):
    self.caches[n_cache].set_entry(
      addr=addr,
      data=data,
      status=state
    )

  def create_transaction(self, n_cache: int, txn: CacheTransaction):
    self.transactions[n_cache].add_transaction(txn)

  def generate_random_memory(self):
    self.mem_state.gen_rand_mem()

  def generate_random_transactions(self):
    for txn_seq in self.transactions:
      txn_seq.generate_rand_sequence(self.n_transactions)

  def save_transactions(self):
    for i, txn_seq in enumerate(self.transactions):
      txn_seq.generate_file(
        os.path.join(self.target_dir, f"txns_{i}.txt"))

  def save_memory(self):
    self.mem_state.save_mem(
      file=os.path.join(self.target_dir, "main_mem.mem"))

  def save_state(self):
    self.save_caches()
    self.save_transactions()
    self.save_memory()

  def rand_choice(self, odds=0.5):
    """Returns true for given odds"""
    if random() < odds:
      return True
    return False

  def rand_index(self, n):
    """Return random index from 0 to n"""
    return randint(0, n)

  def rand_cache_index(self):
    return self.rand_index(self.rand_index(self.n_caches))

  def rand_sharers(self, owner):
    sharers = []
    for idx in range(self.n_caches):
      if idx == owner:
        sharers.append(True)
      else:
        sharers.append(self.rand_choice())

  def get_rand_cacheline_data(self):
    data = []
    for _ in range(self.cacheline_bytes):
      data.append(randint(0, 255))
    return data

  def get_rand_mem_range(self) -> MemoryRange:
    return choice(self.mem_ranges)

  def generate_random_caches(self, n_inited_lines):
    for _ in range(n_inited_lines):
      # Get a random memory range
      rand_mem_range = self.get_rand_mem_range()
      # Get a random address from that memory range
      # Aligned to cache line boundary
      addr = rand_mem_range.get_rand_addr(self.cacheline_bytes)
      # Get data from initialized memory
      data = rand_mem_range.get_data(addr, self.cacheline_bytes)

      # Check if all caches have space for the new entry
      # Skip if not
      not_free_found = False
      for cache in self.caches:
        _, free = cache.get_free_way(cache.get_index(addr))
        if not free:
          not_free_found = True
      if not_free_found:
        continue

      # Check if the address is already stored
      # Skip if yes
      hit_found = False
      for cache in self.caches:
        hit, _, _, _, _ = cache.get_addr(addr)
        if hit:
          hit_found = True
      if hit_found:
        continue

      # Select random number of masters to have that cache line
      n_masters = randint(1, self.n_caches)
      # Randomly select the master indices to have that cache line
      mst_idxs = sample(range(self.n_caches), n_masters)
      # Select whether someone will hold the line in dirty state
      dirty = self.rand_choice(odds=0.5)
      shared = len(mst_idxs) > 1
      owner = -1
      write_data = data
      if dirty:
        # Randomly select the owner
        owner = sample(mst_idxs, 1)[0]
        # All cachelines have the same data
        write_data = self.get_rand_cacheline_data()

      for mst_idx in mst_idxs:
        if mst_idx == owner:
          # Generate random data since data is dirty
          if shared:
            state = CachelineState(CachelineStateEnum.OWNED)
          else:
            state = CachelineState(CachelineStateEnum.MODIFIED)
        else:
          if shared:
            state = CachelineState(CachelineStateEnum.SHARED)
          else:
            state = CachelineState(CachelineStateEnum.EXCLUSIVE)
        try:
          self.set_cache_line(
            mst_idx,
            addr,
            write_data,
            state.get_state_bits()
          )
        except CacheSetFullException:
          pass

  def get_next_timestamp(self, files, cur_time):
    """
    Returns (finish, next_tstamp, addrs_w_same_tstamp).
    If finish == True, it means there are no more timestamps\n
    `addrs_w_same_tstamp` is a list of (idx, addr), which indicates
    the cache index that retires a transaction on this timestamp, and
    the address it retires.
    """
    # Store:
    #  - Timestamps that were found
    #  - Corresponding address
    #  - Corresponding master index
    # There might be situations where some masters have run out of
    # transactions while other ones still have outstanding ones,
    # so this type of tracking is needed
    timestamps = []
    addrs = []
    idxs = []
    addrs_w_tstamp = []
    for i, file in enumerate(files):
      with open(file, "r") as cache_file:
        for line in cache_file:
          words = line.split()
          time = None
          initiator = None
          addr = None
          # Iterate over words (separated by whitespace)
          for word in words:
            # Check which keyword the word is
            # The keywords must appear in the line in this order
            t_idx = word.find("TIME:")
            i_idx = word.find("INITIATOR:")
            a_idx = word.find("ADDR:")
            payload = word.split(":")[1]
            if t_idx != -1:
              time = int(payload)
            if i_idx != -1:
              initiator = bool(int(payload))
              if not initiator:
                # Don't store the time of this timestamp marks an
                # outstanding transaction
                time = None
            if a_idx != -1:
              addr = int(payload, 16)
          # Add to the list only if a transaction was retired on this
          # timestamp
          if time:
            if time > cur_time:
              timestamps.append(time)
              addrs.append(addr)
              idxs.append(i)
              break
    finish = False
    next_tstamp = 0
    if all(x == float("inf") for x in timestamps):
      finish = True
    else:
      next_tstamp = min(timestamps)
      idx_w_same_tstamp = [i for i, x in enumerate(timestamps) if x == next_tstamp]
      for i in idx_w_same_tstamp:
        addrs_w_tstamp.append((idxs[i], addrs[i]))
    return finish, next_tstamp, addrs_w_tstamp

  def reconstruct_state(self):
    """Reconstruct state into Python datatypes"""
    files = []
    start_time = 0
    errors = False
    for i in range(self.n_caches):
      files.append(os.path.join(self.target_dir, f"cache_diff_{i}.txt"))
    while True:
      finish, end_time, addrs = self.get_next_timestamp(files, start_time)
      if finish:
        break
      for i, cache in enumerate(self.caches):
        cache.reconstruct_state(files[i], start_time, end_time)
      self.mem_state.reconstruct_mem(os.path.join(self.target_dir, "main_mem_diff.txt"), start_time, end_time)
      logger.info(f"==================== TIMESTAMP: {end_time} ====================")
      new_errors = self.check_coherency()
      errors = errors or new_errors
      for addr in addrs:
        # Clear outstanding addresses for the ones that were handled this timestamp
        for i in range(self.n_caches):
          if i == addr[0]:
            continue
          if self.caches[i].clear_outstanding_addr(addr[1]):
            logger.info("Removing address from outstanding")
            self.print_info(addr=addr[1], cache_idx=i)
      start_time = end_time
    return errors

  def print_info(self, level=logging.INFO, addr=None, cache_idx=None, state=None,
                  set=None, way=None):
    if addr is not None:
      logger.log(level, msg=f"Address: {hex(addr)}")
    if cache_idx is not None:
      logger.log(level, msg=f"Cache: {cache_idx}")
    if state is not None:
      logger.log(level, msg=f"State: {state}")
    if set is not None:
      logger.log(level, msg=f"Set: {set}")
    if way is not None:
      logger.log(level, msg=f"Way: {way}")

  def check_coherency(self):
    """Check that caches and main memory are coherent.
    Test cases:
      - Modified cache line must not be in Exclusive state
      - Modified cache line must have it somewhere in either Owned or Modified state
      - Cache line states must be compatible (e.g. Modified && Shared is not allowed)
      """

    logger.info("Starting coherency check")
    error = False
    debug = self.debug

    for mem_range in self.mem_ranges:
      for addr in range(
                mem_range.start_addr,
                mem_range.end_addr,
                self.cacheline_bytes):
        cached, shared = mem_range.get_addr_properties(addr)
        skip_addr = False
        if not (shared and cached):
          # Currently only checking shared and cached regions
          continue

        # Check if there are addresses which have outstanding transactions
        # This occurs when a snoop transaction has modified a cache line, but
        # the transaction itself didnt finish yet
        for cache in self.caches:
          if addr in cache.outstanding:
            skip_addr = True
            logger.info("Skipping address due to an outstanding transaction")
            self.print_info(logging.INFO, addr=addr)
            break
        if skip_addr:
          continue

        cacheline = mem_range.get_data(addr, self.cacheline_bytes)
        states: List[CachelineState] = []
        modified = False
        owner_found = False

        # Check all caches whether they hold a copy
        # Compute moesi state
        # Check that modified copy is not in Exclusive state
        # Monitor whether a modified copy exists
        # Monitor whether an owner is found
        for i, cache in enumerate(self.caches):
          hit, data, state, set, way = cache.get_addr(addr)
          moesi: CachelineState = state
          if hit:
            logger.info("Cacheline found")
            self.print_info(logging.INFO, addr=addr, cache_idx=i, state=moesi.state.name, set=set, way=way)
            if data != cacheline:
              if moesi.state != CachelineStateEnum.INVALID:
                modified = True
              if moesi.state == CachelineStateEnum.EXCLUSIVE:
                logger.error("A modified cache line in Exclusive state")
                self.print_info(logging.ERROR, addr=addr, cache_idx=i, state=moesi.state.name, set=set, way=way)
                error = True
                if debug: import pdb; pdb.set_trace()
            if moesi.state in \
              [CachelineStateEnum.OWNED, CachelineStateEnum.MODIFIED]:
              owner_found = True
          states.append(moesi)

        if modified and not owner_found:
          error = True
          logger.error("A modified cache line without owner was found!")
          self.print_info(logging.ERROR, addr=addr, set=set)
          if debug: import pdb; pdb.set_trace()

        # Compare cacheline states
        for i in range(len(states)):
          for j in range(len(states)):
            if i == j:
              continue
            res = states[i].check_compatibility(states[j].state)
            if not res:
              a_hit, _, a_state, a_set, a_way = self.caches[i].get_addr(addr)
              b_hit, _, b_state, b_set, b_way = self.caches[j].get_addr(addr)
              logger.error("Two cache lines in incompatible states!")
              self.print_info(
                logging.ERROR,
                addr=addr,
                cache_idx=(i, j),
                state=(states[i].state.name, states[j].state.name),
                set=(a_set, b_set),
                way=(a_way, b_way)
              )
              error = True
              if debug: import pdb; pdb.set_trace()
    logger.info("Coherency check finished")
    return error

  def save_caches(self):
    for i, cache in enumerate(self.caches):
      cache.save_state(
        data_file=os.path.join(self.target_dir, f"data_mem_{i}.mem"),
        tag_file=os.path.join(self.target_dir, f"tag_mem_{i}.mem"),
        state_file=os.path.join(self.target_dir, f"state_{i}.mem")
      )

  def run(self):
    errors = False
    if self.check:
      input("Press enter after simulation finishes to start coherency check")
      errors = self.reconstruct_state()
    return errors



class RandomTest(CacheCoherencyTest):
  def __init__(
      self,
      **kwargs
  ):
    super().__init__(**kwargs)
    self.define_test()
    errors = self.run()
    if errors:
      print("Errors found")

  def define_test(self):
    self.add_memory_range(MemoryRange(
        cached=True, shared=True, start_addr=0, end_addr=0x0000_1000
    ))
    self.generate_random_memory()
    self.generate_random_transactions()
    self.generate_random_caches(n_inited_lines=100)
    self.check_coherency()
    self.save_state()

class ConflictTest(CacheCoherencyTest):
  def __init__(
      self,
      **kwargs
  ):
    super().__init__(**kwargs)
    self.define_test()

  def define_test(self):
    self.add_memory_range(MemoryRange(
        cached=True, shared=True, start_addr=0, end_addr=0x0010_0000
    ))
    self.generate_random_memory()
    self.create_transaction(n_cache=0, txn=CacheTransaction(
      addr=0,
      op=CacheReqOp.REQ_LOAD,
      size=int(log2(self.dw)),
      shareability=1,
      cached=True,
      time=10
    ))
    self.create_transaction(n_cache=1, txn=CacheTransaction(
      addr=0,
      op=CacheReqOp.REQ_LOAD,
      size=int(log2(self.dw)),
      shareability=1,
      cached=True,
      time=10
    ))
    self.save_state()


if __name__ == "__main__":
  import argparse
  from random import seed
  import numpy as np
  parser = argparse.ArgumentParser(
    description=('Script to write data to a file'
                 'based on address space.')
  )
  parser.add_argument(
    '--addr_width',
    type=int,
    help='AXI address width'
  )
  parser.add_argument(
    '--data_width',
    type=int,
    help='AXI data width'
  )
  parser.add_argument(
    '--word_width',
    type=int,
    help='Width of a word in the cache'
  )
  parser.add_argument(
    '--cacheline_words',
    type=int,
    help='Number of words in a cacheline'
  )
  parser.add_argument(
    '--ways',
    type=int,
    help='Number of ways in the cache'
  )
  parser.add_argument(
    '--sets',
    type=int,
    help='Number of sets in the cache'
  )
  parser.add_argument(
    '--n_caches',
    type=int,
    help='Number of cached masters in the test'
  )
  parser.add_argument(
    '--n_transactions',
    type=int,
    help='Number of transactions generated per cached master'
  )
  parser.add_argument(
    '--target_dir',
    type=str,
    help='Target directory for generated files'
  )
  parser.add_argument(
    '--seed',
    type=int,
    help="Seed for the simulation",
    default=None,
    nargs='?'
  )
  parser.add_argument(
    '--check',
    action='store_true',
    help="Check for coherency once prompted"
  )
  parser.add_argument(
    '--debug',
    action='store_true',
    help="Debug mode. During coherency checking, will open pdb when error is encountered."
  )
  parsed_args = vars(parser.parse_args())
  if parsed_args.get("seed", None):
    seed(parsed_args["seed"])
    np.random.seed(parsed_args["seed"])
  cct = RandomTest(**parsed_args)

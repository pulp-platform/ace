from typing import List, Tuple
from math import log2
from enum import Enum

class StateBits(Enum):
  VALID_IDX = 0
  SHARED_IDX = 1
  DIRTY_IDX = 2

class CachelineStateEnum(Enum):
  MODIFIED = 0
  OWNED = 1
  EXCLUSIVE = 2
  SHARED = 3
  INVALID = 4

class CachelineState:
  def __init__(self, state: CachelineStateEnum = CachelineStateEnum.INVALID):
    self.state = state

  def from_state_bits(self, state_bits: List[StateBits]):
    if state_bits[StateBits.VALID_IDX.value] == 0:
      self.state = CachelineStateEnum.INVALID
    elif (state_bits[StateBits.SHARED_IDX.value] and
          state_bits[StateBits.DIRTY_IDX.value]):
      self.state = CachelineStateEnum.OWNED
    elif state_bits[StateBits.SHARED_IDX.value]:
      self.state = CachelineStateEnum.SHARED
    elif state_bits[StateBits.DIRTY_IDX.value]:
      self.state = CachelineStateEnum.MODIFIED
    elif state_bits[StateBits.VALID_IDX.value]:
      self.state = CachelineStateEnum.EXCLUSIVE
    else:
      raise Exception("Unexpected state")

  def get_state_bits(self):
    state_bits = [False, False, False]
    if self.state == CachelineStateEnum.MODIFIED:
      state_bits[StateBits.VALID_IDX.value] = True
      state_bits[StateBits.DIRTY_IDX.value] = True
    elif self.state == CachelineStateEnum.OWNED:
      state_bits[StateBits.VALID_IDX.value] = True
      state_bits[StateBits.SHARED_IDX.value] = True
      state_bits[StateBits.DIRTY_IDX.value] = True
    elif self.state == CachelineStateEnum.EXCLUSIVE:
      state_bits[StateBits.VALID_IDX.value] = True
    elif self.state == CachelineStateEnum.SHARED:
      state_bits[StateBits.VALID_IDX.value] = True
      state_bits[StateBits.SHARED_IDX.value] = True
    return state_bits

  def check_compatibility(self, other: CachelineStateEnum):
    if self.state == CachelineStateEnum.MODIFIED:
      if other == CachelineStateEnum.INVALID:
        return True
      return False
    elif self.state == CachelineStateEnum.OWNED:
      if other in [CachelineStateEnum.INVALID,
                   CachelineStateEnum.SHARED]:
        return True
      return False
    elif self.state == CachelineStateEnum.EXCLUSIVE:
      if other == CachelineStateEnum.INVALID:
        return True
      return False
    elif self.state == CachelineStateEnum.SHARED:
      if other in [CachelineStateEnum.EXCLUSIVE,
                   CachelineStateEnum.MODIFIED]:
        return False
      return True
    elif self.state == CachelineStateEnum.INVALID:
      return True
    else:
      raise Exception("Unexpected state")

class CacheSetFullException(Exception):
  pass

class CacheState:
  def __init__(
      self,
      addr_width,
      data_width,
      word_width,
      cacheline_words,
      ways,
      sets
    ):
    self.aw = addr_width
    self.dw = data_width
    self.word_width = word_width
    self.cacheline_words = cacheline_words
    self.ways = ways
    self.sets = sets

    self.bytes_per_word = self.dw // 8
    self.cacheline_bytes = \
      self.cacheline_words * self.word_width // 8
    self.block_offset_bits = int(log2(self.cacheline_bytes))
    self.index_bits = int(log2(self.sets))
    self.tag_bits = \
      self.aw - self.block_offset_bits - self.index_bits

    self.index_mask = ((1 << self.index_bits) - 1) << self.block_offset_bits
    self.tag_mask = ((1 << self.tag_bits) - 1) << (self.block_offset_bits + self.index_bits)

    self.cache_status = None
    self.cache_data   = None
    self.cache_tag    = None

    # Store which cache lines are "outstanding"
    # i.e. a snoop has modified their status, but the
    # respective transaction has not finished
    self.outstanding = []

  def init_cache(self):
    # multi-dimensional lists must be initialized in steps
    # to ensure that unique copies are created, instead of
    # references to one
    self.cache_status = self.sets * [None]
    self.cache_tag = self.sets * [None]
    self.cache_data = self.sets * [None]
    for set in range(self.sets):
      self.cache_status[set] = self.ways * [None]
      self.cache_tag[set] = self.ways * [None]
      self.cache_data[set] = self.ways * [None]
      for way in range(self.ways):
        self.cache_status[set][way] = 3 * [False]
        self.cache_tag[set][way] = 0
        self.cache_data[set][way] = self.cacheline_bytes * [0]

  def get_index(self, addr):
    return (addr & self.index_mask) >> self.block_offset_bits

  def get_tag(self, addr):
    return (addr & self.tag_mask) >> (self.block_offset_bits + self.index_bits)

  def get_addr(self, addr):
    """Returns: (hit, data, state, set, way)"""
    set = self.get_index(addr)
    hit = False
    final_way = 0
    data = []
    state = CachelineState()
    tag_bits = self.get_tag(addr)
    for way in range(self.ways):
      if ((self.cache_tag[set][way] == tag_bits) and
          (self.cache_status[set][way][StateBits.VALID_IDX.value])):
        hit = self.cache_status[set][way][StateBits.VALID_IDX.value]
        data = self.cache_data[set][way]
        state.from_state_bits(self.cache_status[set][way])
        final_way = way
    return hit, data, state, set, final_way

  def get_free_way(self, set):
    """Get first free (non-valid) way in a set."""
    was_free = False
    way_idx = 0
    for i, way in enumerate(self.cache_status[set]):
      if not way[StateBits.VALID_IDX.value]:
        way_idx = i
        was_free = True
        break
    return way_idx, was_free

  def set_entry(
      self,
      addr: int,
      data: List[int],
      status: List[bool]
    ):
    """Write cacheline corresponding to addr with data and status.
    Assumes we write the whole cache line byte-by-byte
    """
    set_idx = self.get_index(addr)
    way_idx, was_free = self.get_free_way(set_idx)
    if not was_free:
      raise CacheSetFullException
    for byte_idx in range(self.cacheline_bytes):
      self.cache_data[set_idx][way_idx][byte_idx] = \
        data[byte_idx]
    self.cache_tag[set_idx][way_idx] = self.get_tag(addr)
    self.cache_status[set_idx][way_idx][0] = status[0]
    self.cache_status[set_idx][way_idx][1] = status[1]
    self.cache_status[set_idx][way_idx][2] = status[2]

  def save_data(
    self,
    file
  ):
    with open(file, "w") as data_file:
      for set in range(self.sets):
        fmt = [f"@{set:x}"]
        any_valid = False
        for way in range(self.ways):
          if (self.cache_status[set][way][StateBits.VALID_IDX.value]):
            any_valid = True
          for byte in self.cache_data[set][way]:
            fmt += [f"{byte:2x}"]
        if any_valid:
          data_file.write(" ".join(fmt) + "\n")

  def save_tag(
    self,
    file
  ):
    with open(file, "w") as tag_file:
      for set in range(self.sets):
        fmt = [f"@{set:x}"]
        any_valid = False
        for way in range(self.ways):
          if (self.cache_status[set][way][StateBits.VALID_IDX.value]):
            any_valid = True
          fmt += [f"{self.cache_tag[set][way]:2x}"]
        if any_valid:
          tag_file.write(" ".join(fmt) + "\n")

  def status_arr_to_int(self, bool_arr):
    bin_str = ''.join(['1' if x else '0' for x in list(reversed(bool_arr))])
    return int(bin_str, 2)

  def save_status(
    self,
    file
  ):
    with open(file, "w") as state_file:
      for set in range(self.sets):
        fmt = [f"@{set:x}"]
        any_valid = False
        for way in range(self.ways):
          if (self.cache_status[set][way][StateBits.VALID_IDX.value]):
            any_valid = True
          fmt += [f"{self.status_arr_to_int(self.cache_status[set][way]):03b}"]
        if any_valid:
          state_file.write(" ".join(fmt) + "\n")

  def save_state(
      self,
      data_file="data_mem.mem",
      tag_file="tag_mem.mem",
      state_file="state.mem"
  ):
    self.save_data(data_file)
    self.save_tag(tag_file)
    self.save_status(state_file)

  def clear_outstanding_addr(self, addr):
    """Remove addr from self.outstanding.
    Returns True if the address was stored.
    Returns False if it wasn't."""
    try:
      self.outstanding.remove(addr)
      return True
    except ValueError:
      return False

  def reconstruct_state(
      self,
      file,
      start_time,
      end_time
  ):
    with open(file, "r") as state_file:
      for line in state_file:
        words = line.split()
        addr = None
        time = None
        initiator = None
        set = None
        way = None
        tag = None
        status = None
        data = None
        modify = True
        for word in words:
          time_idx = word.find("TIME:")
          initiator_idx = word.find("INITIATOR:")
          addr_idx = word.find("ADDR:")
          set_idx = word.find("SET:")
          way_idx = word.find("WAY")
          tag_idx = word.find("TAG:")
          status_idx = word.find("STATUS:")
          data_idx = word.find("DATA:")
          payload = word.split(":")[1]
          if time_idx != -1:
            time = int(payload)
          if addr_idx != -1:
            addr = int(payload, 16)
          if set_idx != -1:
            set = int(payload)
          if initiator_idx != -1:
            initiator = bool(int(payload))
          if way_idx != -1:
            way = int(payload)
          if tag_idx != -1:
            tag = int(payload, 16)
          if status_idx != -1:
            status = [char == '1' for char in payload]
            status.reverse()
          if data_idx != -1:
            data = [int(x, 16) for x in payload.strip("[]").split(",")]
        if None in [time,initiator,set,way,tag,status,data]:
          # A row with only time and address present indicates
          # a finished transaction which wasn't cached but might've
          # modified other cache lines by snooping
          if None in [time, addr]:
            print("Unexpected state")
            import pdb; pdb.set_trace()
          modify = False
        if time > end_time:
          return time
        if time <= start_time:
          continue
        if modify:
          self.cache_data[set][way] = data
          self.cache_tag[set][way] = tag
          self.cache_status[set][way] = status
        if not initiator:
          self.outstanding.append(addr)

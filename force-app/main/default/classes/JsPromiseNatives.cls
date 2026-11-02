/** Bounded Promise jobs for synchronous host work. No timer, network, or external event loop. */
public class JsPromiseNatives {
  public static Boolean enabled = false;
  public class State {
    public String status = 'pending';
    public JsValue value;
    public List<Reaction> reactions = new List<Reaction>();
  }
  public class Capability {
    public JsValue promise;
    public Boolean called = false;
  }
  public class Reaction {
    public JsValue target, onFulfilled, onRejected;
    public Boolean adopt = false;
  }
  public class Job {
    public JsValue source, thenable, thenFunction;
    public Reaction reaction;
  }
  public static void install(JsScope scope, JsRuntime runtime) {
    runtime.promisePrototype = new JsValue('object');
    JsValue ctor = JsValue.nativeFunction('Promise.construct');
    ctor.constructorPrototype = runtime.promisePrototype;
    ctor.props = new Map<String, JsValue>();
    for (String name : new List<String>{ 'resolve', 'reject' }) {
      ctor.props.put(name, JsValue.nativeFunction('Promise.' + name));
      ctor.attributes(name, false, true, true);
    }
    runtime.promisePrototype.props.put('constructor', ctor);
    runtime.promisePrototype.attributes('constructor', false, true, true);
    for (String name : new List<String>{ 'then', 'catch' }) {
      runtime.promisePrototype.props.put(name, JsValue.nativeFunction('promise.' + name));
      runtime.promisePrototype.attributes(name, false, true, true);
    }
    scope.declare('Promise', ctor, true);
  }
  private static Boolean callable(JsValue value) {
    return value != null && (value.kind == 'function' || value.kind == 'native');
  }
  private static Boolean resource(JsException error) {
    return error.getMessage().startsWith('BudgetError:') ||
      error.getMessage().startsWith('BytecodeError:');
  }
  private static JsValue create(JsRuntime runtime) {
    runtime.budget.allocate(1);
    JsValue value = new JsValue('promise');
    value.promiseState = new State();
    value.explicitPrototype = true;
    value.prototypeParent = runtime.promisePrototype;
    return value;
  }
  private static List<JsValue> resolvingFunctions(JsValue target, JsRuntime runtime) {
    runtime.budget.allocate(3);
    Capability cap = new Capability();
    cap.promise = target;
    JsValue resolve = JsValue.nativeFunction('promise.resolveInternal'),
      reject = JsValue.nativeFunction('promise.rejectInternal');
    resolve.promiseCapability = cap;
    reject.promiseCapability = cap;
    return new List<JsValue>{ resolve, reject };
  }
  public static JsValue invokeCapability(
    JsValue functionValue,
    List<JsValue> args,
    JsRuntime runtime
  ) {
    Capability cap = functionValue.promiseCapability;
    if (cap == null)
      throw new JsException('TypeError: Missing Promise capability.');
    if (!cap.called) {
      cap.called = true;
      JsValue value = args.isEmpty() ? new JsValue('undefined') : args[0];
      if (functionValue.nativeName == 'promise.resolveInternal')
        resolveValue(cap.promise, value, runtime);
      else
        settle(cap.promise, 'rejected', value, runtime);
    }
    return new JsValue('undefined');
  }
  public static JsValue construct(List<JsValue> args, JsRuntime runtime) {
    if (args.size() != 1 || !callable(args[0]))
      throw new JsException('TypeError: Promise executor must be callable.');
    JsValue target = create(runtime);
    List<JsValue> functions = resolvingFunctions(target, runtime);
    try {
      runtime.invoke(args[0], functions, null);
    } catch (JsThrownException error) {
      invokeCapability(functions[1], new List<JsValue>{ error.value }, runtime);
    } catch (JsException error) {
      if (resource(error))
        throw error;
      invokeCapability(functions[1], new List<JsValue>{ runtime.languageError(error) }, runtime);
    }
    return target;
  }
  private static void enqueueReaction(JsValue source, Reaction reaction, JsRuntime runtime) {
    Job job = new Job();
    job.source = source;
    job.reaction = reaction;
    runtime.enqueuePromiseJob(job);
  }
  private static void subscribe(JsValue source, Reaction reaction, JsRuntime runtime) {
    runtime.budget.allocate(1);
    if (source.promiseState.status == 'pending')
      source.promiseState.reactions.add(reaction);
    else
      enqueueReaction(source, reaction, runtime);
  }
  private static void settle(JsValue promise, String status, JsValue value, JsRuntime runtime) {
    if (promise.promiseState.status != 'pending')
      return;
    State state = promise.promiseState;
    state.status = status;
    state.value = value;
    for (Reaction reaction : state.reactions)
      enqueueReaction(promise, reaction, runtime);
    state.reactions.clear();
  }
  private static void resolveValue(JsValue target, JsValue value, JsRuntime runtime) {
    if (target.promiseState.status != 'pending')
      return;
    if (target === value) {
      settle(
        target,
        'rejected',
        runtime.languageError(new JsException('TypeError: Promise cannot resolve itself.')),
        runtime
      );
      return;
    }
    if (value.kind == 'promise') {
      Reaction reaction = new Reaction();
      reaction.target = target;
      reaction.adopt = true;
      subscribe(value, reaction, runtime);
      return;
    }
    if (JsObjectNatives.objectLike(value)) {
      JsValue thenFunction;
      try {
        thenFunction = runtime.getProperty(value, 'then');
      } catch (JsThrownException error) {
        settle(target, 'rejected', error.value, runtime);
        return;
      } catch (JsException error) {
        if (resource(error))
          throw error;
        settle(target, 'rejected', runtime.languageError(error), runtime);
        return;
      }
      if (callable(thenFunction)) {
        Job job = new Job();
        job.source = target;
        job.thenable = value;
        job.thenFunction = thenFunction;
        runtime.enqueuePromiseJob(job);
        return;
      }
    }
    settle(target, 'fulfilled', value, runtime);
  }
  public static JsValue invoke(
    String name,
    List<JsValue> args,
    JsValue receiver,
    JsRuntime runtime
  ) {
    if (name == 'Promise.construct')
      throw new JsException('TypeError: Promise requires new.');
    if (name == 'Promise.resolve' || name == 'Promise.reject') {
      if (args.size() > 1)
        throw new JsException('TypeError: Promise settlement accepts at most one value.');
      JsValue value = args.isEmpty() ? new JsValue('undefined') : args[0];
      if (name == 'Promise.resolve' && value.kind == 'promise')
        return value;
      JsValue target = create(runtime);
      if (name == 'Promise.resolve')
        resolveValue(target, value, runtime);
      else
        settle(target, 'rejected', value, runtime);
      return target;
    }
    if (receiver == null || receiver.kind != 'promise')
      throw new JsException('TypeError: Promise method requires a Promise receiver.');
    if (args.size() > (name == 'promise.catch' ? 1 : 2))
      throw new JsException('TypeError: Too many Promise handlers.');
    JsValue target = create(runtime);
    Reaction reaction = new Reaction();
    reaction.target = target;
    reaction.onFulfilled = name == 'promise.catch' || args.isEmpty() ? null : args[0];
    reaction.onRejected = name == 'promise.catch'
      ? (args.isEmpty() ? null : args[0])
      : args.size() < 2 ? null : args[1];
    subscribe(receiver, reaction, runtime);
    return target;
  }
  public static void runJob(Job job, JsRuntime runtime) {
    runtime.budget.tick();
    if (job.thenFunction != null) {
      List<JsValue> functions = resolvingFunctions(job.source, runtime);
      try {
        runtime.invoke(job.thenFunction, functions, job.thenable);
      } catch (JsThrownException error) {
        invokeCapability(functions[1], new List<JsValue>{ error.value }, runtime);
      } catch (JsException error) {
        if (resource(error))
          throw error;
        invokeCapability(functions[1], new List<JsValue>{ runtime.languageError(error) }, runtime);
      }
      return;
    }
    State state = job.source.promiseState;
    Reaction reaction = job.reaction;
    if (reaction.adopt) {
      if (state.status == 'fulfilled')
        resolveValue(reaction.target, state.value, runtime);
      else
        settle(reaction.target, 'rejected', state.value, runtime);
      return;
    }
    JsValue handler = state.status == 'fulfilled' ? reaction.onFulfilled : reaction.onRejected;
    if (!callable(handler)) {
      if (state.status == 'fulfilled')
        resolveValue(reaction.target, state.value, runtime);
      else
        settle(reaction.target, 'rejected', state.value, runtime);
      return;
    }
    try {
      resolveValue(
        reaction.target,
        runtime.invoke(handler, new List<JsValue>{ state.value }, null),
        runtime
      );
    } catch (JsThrownException error) {
      settle(reaction.target, 'rejected', error.value, runtime);
    } catch (JsException error) {
      if (resource(error))
        throw error;
      settle(reaction.target, 'rejected', runtime.languageError(error), runtime);
    }
  }
  public static JsValue finish(JsValue value, JsRuntime runtime) {
    runtime.drainPromiseJobs();
    if (value.kind != 'promise')
      return value;
    if (value.promiseState.status == 'rejected')
      throw JsThrownException.carrying(value.promiseState.value);
    if (value.promiseState.status != 'fulfilled')
      throw new JsException(
        'TypeError: Pending Promise has no runnable work in this synchronous host.'
      );
    return value.promiseState.value;
  }
}

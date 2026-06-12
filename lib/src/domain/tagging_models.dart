enum TagDirection { income, expense, neutral }

enum TagDefinitionSource { builtIn, system, custom }

enum TagDefinitionStatus { active, deprecated }

final class TagDefinition {
  final String id;
  final int schemaVersion;
  final String displayName;
  final String classificationId;
  final TagDirection direction;
  final String colorToken;
  final String iconToken;
  final TagDefinitionSource source;
  final TagDefinitionStatus status;
  final Set<String> aliases;

  const TagDefinition({
    required this.id,
    this.schemaVersion = 1,
    required this.displayName,
    required this.classificationId,
    required this.direction,
    required this.colorToken,
    required this.iconToken,
    required this.source,
    this.status = TagDefinitionStatus.active,
    this.aliases = const {},
  });
}

enum TagAssignmentSource {
  manual,
  propagation,
  merchantHistory,
  userCorrection,
  deterministicRule,
  localModel,
  spendingMemory,
  remoteAi,
}

final class TagAssignment {
  final String transactionId;
  final String tagId;
  final TagAssignmentSource source;
  final double confidence;
  final String reasonCode;
  final String? ruleOrModelVersion;
  final String operationId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TagAssignment({
    required this.transactionId,
    required this.tagId,
    required this.source,
    required this.confidence,
    required this.reasonCode,
    this.ruleOrModelVersion,
    required this.operationId,
    required this.createdAt,
    required this.updatedAt,
  });
}

final class TaggingTransaction {
  final String id;
  final String sourceId;
  final String sourceTransactionId;
  final String merchant;
  final String? protectedPhoneSuffix;
  final String direction;
  final String kind;
  final int amountMinor;
  final String currency;
  final DateTime occurredAt;

  const TaggingTransaction({
    required this.id,
    required this.sourceId,
    required this.sourceTransactionId,
    required this.merchant,
    this.protectedPhoneSuffix,
    required this.direction,
    required this.kind,
    required this.amountMinor,
    required this.currency,
    required this.occurredAt,
  });
}

final class TaggingCandidate {
  final String tagId;
  final double confidence;
  final TagAssignmentSource source;
  final String reasonCode;
  final String? version;
  final Map<String, Object?> evidence;

  const TaggingCandidate({
    required this.tagId,
    required this.confidence,
    required this.source,
    required this.reasonCode,
    this.version,
    this.evidence = const {},
  });
}

enum TaggingAction { suppress, suggest, autoApply }

final class TagSuggestion {
  final TaggingTransaction transaction;
  final TaggingCandidate? candidate;
  final TaggingAction action;

  const TagSuggestion({
    required this.transaction,
    required this.candidate,
    required this.action,
  });
}

final class TaggingRequest {
  final List<TaggingTransaction> transactions;
  final bool allowRemoteAi;

  const TaggingRequest({
    required this.transactions,
    this.allowRemoteAi = false,
  });
}

final class TagSuggestionSet {
  final List<TagSuggestion> suggestions;
  final DateTime generatedAt;

  const TagSuggestionSet({
    required this.suggestions,
    required this.generatedAt,
  });
}

enum TaggingScope {
  transactionOnly,
  matchingUntagged,
  allMatching,
  futureMatching,
}

final class TaggingDecision {
  final String transactionId;
  final String tagId;
  final TaggingScope scope;

  const TaggingDecision({
    required this.transactionId,
    required this.tagId,
    required this.scope,
  });
}

final class TaggingPreview {
  final TaggingDecision decision;
  final List<String> affectedTransactionIds;
  final int alreadyTaggedCount;
  final DateTime? earliest;
  final DateTime? latest;

  const TaggingPreview({
    required this.decision,
    required this.affectedTransactionIds,
    required this.alreadyTaggedCount,
    this.earliest,
    this.latest,
  });
}

final class TaggingOperation {
  final String id;
  final TaggingDecision decision;
  final Map<String, TagAssignment?> previousAssignments;
  final DateTime createdAt;
  final DateTime reversibleUntil;

  const TaggingOperation({
    required this.id,
    required this.decision,
    required this.previousAssignments,
    required this.createdAt,
    required this.reversibleUntil,
  });
}

final class AutoTagRequest {
  final List<String> transactionIds;
  final bool allowRemoteAi;
  final int maximumAutoApply;

  const AutoTagRequest({
    required this.transactionIds,
    this.allowRemoteAi = false,
    this.maximumAutoApply = 30,
  });
}

final class TaggingRun {
  final int considered;
  final int applied;
  final int suggested;
  final int suppressed;

  const TaggingRun({
    required this.considered,
    required this.applied,
    required this.suggested,
    required this.suppressed,
  });
}

// Built-in tag definitions ─────────────────────────────────────────────────────

const builtInTagCatalog = <TagDefinition>[
  TagDefinition(
    id: 'income',
    displayName: 'Income',
    classificationId: 'income_growth',
    direction: TagDirection.income,
    colorToken: 'tag.income',
    iconToken: 'icon.income',
    source: TagDefinitionSource.builtIn,
    aliases: {'salary', 'wages'},
  ),
  TagDefinition(
    id: 'investment',
    displayName: 'Investment',
    classificationId: 'income_growth',
    direction: TagDirection.expense,
    colorToken: 'tag.investment',
    iconToken: 'icon.investment',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'savings',
    displayName: 'Savings',
    classificationId: 'income_growth',
    direction: TagDirection.expense,
    colorToken: 'tag.savings',
    iconToken: 'icon.savings',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'salary',
    displayName: 'Salary',
    classificationId: 'income_growth',
    direction: TagDirection.income,
    colorToken: 'tag.salary',
    iconToken: 'icon.salary',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'groceries',
    displayName: 'Groceries',
    classificationId: 'food_dining',
    direction: TagDirection.expense,
    colorToken: 'tag.groceries',
    iconToken: 'icon.groceries',
    source: TagDefinitionSource.builtIn,
    aliases: {'supermarket', 'food shopping'},
  ),
  TagDefinition(
    id: 'food_dining',
    displayName: 'Food & Dining',
    classificationId: 'food_dining',
    direction: TagDirection.expense,
    colorToken: 'tag.food',
    iconToken: 'icon.food',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'shopping',
    displayName: 'Shopping',
    classificationId: 'shopping_lifestyle',
    direction: TagDirection.expense,
    colorToken: 'tag.shopping',
    iconToken: 'icon.shopping',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'transport',
    displayName: 'Transport',
    classificationId: 'transport_travel',
    direction: TagDirection.expense,
    colorToken: 'tag.transport',
    iconToken: 'icon.transport',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'utilities',
    displayName: 'Utilities',
    classificationId: 'housing_utilities',
    direction: TagDirection.expense,
    colorToken: 'tag.utilities',
    iconToken: 'icon.utilities',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'bills',
    displayName: 'Bills',
    classificationId: 'housing_utilities',
    direction: TagDirection.expense,
    colorToken: 'tag.bills',
    iconToken: 'icon.bills',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'rent',
    displayName: 'Rent',
    classificationId: 'housing_utilities',
    direction: TagDirection.expense,
    colorToken: 'tag.rent',
    iconToken: 'icon.rent',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'fuel',
    displayName: 'Fuel',
    classificationId: 'transport_travel',
    direction: TagDirection.expense,
    colorToken: 'tag.fuel',
    iconToken: 'icon.fuel',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'airtime',
    displayName: 'Airtime',
    classificationId: 'telecom_subscriptions',
    direction: TagDirection.expense,
    colorToken: 'tag.airtime',
    iconToken: 'icon.airtime',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'minutes',
    displayName: 'Minutes',
    classificationId: 'telecom_subscriptions',
    direction: TagDirection.expense,
    colorToken: 'tag.minutes',
    iconToken: 'icon.minutes',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'data_bundles',
    displayName: 'Data/Bundles',
    classificationId: 'telecom_subscriptions',
    direction: TagDirection.expense,
    colorToken: 'tag.data',
    iconToken: 'icon.data',
    source: TagDefinitionSource.builtIn,
    aliases: {'data', 'bundles', 'internet'},
  ),
  TagDefinition(
    id: 'loan',
    displayName: 'Loan',
    classificationId: 'finance_obligations',
    direction: TagDirection.neutral,
    colorToken: 'tag.loan',
    iconToken: 'icon.loan',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'loan_repayment',
    displayName: 'Loan Repayment',
    classificationId: 'finance_obligations',
    direction: TagDirection.expense,
    colorToken: 'tag.loan_repayment',
    iconToken: 'icon.loan_repayment',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'insurance',
    displayName: 'Insurance',
    classificationId: 'finance_obligations',
    direction: TagDirection.expense,
    colorToken: 'tag.insurance',
    iconToken: 'icon.insurance',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'subscriptions',
    displayName: 'Subscriptions',
    classificationId: 'telecom_subscriptions',
    direction: TagDirection.expense,
    colorToken: 'tag.subscriptions',
    iconToken: 'icon.subscriptions',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'transfer',
    displayName: 'Transfer',
    classificationId: 'finance_obligations',
    direction: TagDirection.neutral,
    colorToken: 'tag.transfer',
    iconToken: 'icon.transfer',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'debt',
    displayName: 'Debt',
    classificationId: 'finance_obligations',
    direction: TagDirection.expense,
    colorToken: 'tag.debt',
    iconToken: 'icon.debt',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'entertainment',
    displayName: 'Entertainment',
    classificationId: 'entertainment_leisure',
    direction: TagDirection.expense,
    colorToken: 'tag.entertainment',
    iconToken: 'icon.entertainment',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'health',
    displayName: 'Health',
    classificationId: 'health_wellness',
    direction: TagDirection.expense,
    colorToken: 'tag.health',
    iconToken: 'icon.health',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'education',
    displayName: 'Education',
    classificationId: 'education_growth',
    direction: TagDirection.expense,
    colorToken: 'tag.education',
    iconToken: 'icon.education',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'personal',
    displayName: 'Personal',
    classificationId: 'other',
    direction: TagDirection.expense,
    colorToken: 'tag.personal',
    iconToken: 'icon.personal',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'gifts',
    displayName: 'Gifts',
    classificationId: 'other',
    direction: TagDirection.expense,
    colorToken: 'tag.gifts',
    iconToken: 'icon.gifts',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'vacation',
    displayName: 'Vacation',
    classificationId: 'transport_travel',
    direction: TagDirection.expense,
    colorToken: 'tag.vacation',
    iconToken: 'icon.vacation',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'business',
    displayName: 'Business',
    classificationId: 'business_operations',
    direction: TagDirection.neutral,
    colorToken: 'tag.business',
    iconToken: 'icon.business',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'business_meetings',
    displayName: 'Business Meetings',
    classificationId: 'business_operations',
    direction: TagDirection.expense,
    colorToken: 'tag.business_meetings',
    iconToken: 'icon.business_meetings',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'fuel_etims',
    displayName: 'Fuel (eTIMS)',
    classificationId: 'business_operations',
    direction: TagDirection.expense,
    colorToken: 'tag.fuel_etims',
    iconToken: 'icon.fuel',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'other_business',
    displayName: 'Other Business',
    classificationId: 'business_operations',
    direction: TagDirection.expense,
    colorToken: 'tag.other_business',
    iconToken: 'icon.business',
    source: TagDefinitionSource.builtIn,
  ),
  TagDefinition(
    id: 'other',
    displayName: 'Other',
    classificationId: 'other',
    direction: TagDirection.neutral,
    colorToken: 'tag.other',
    iconToken: 'icon.other',
    source: TagDefinitionSource.builtIn,
  ),
];

// Stable mapping from legacy display-name strings to tag IDs.
const legacyTagNameToId = <String, String>{
  'income': 'income',
  'investment': 'investment',
  'savings': 'savings',
  'salary': 'salary',
  'groceries': 'groceries',
  'food & dining': 'food_dining',
  'shopping': 'shopping',
  'transport': 'transport',
  'utilities': 'utilities',
  'bills': 'bills',
  'rent': 'rent',
  'fuel': 'fuel',
  'airtime': 'airtime',
  'minutes': 'minutes',
  'data/bundles': 'data_bundles',
  'loan': 'loan',
  'loan repayment': 'loan_repayment',
  'insurance': 'insurance',
  'subscriptions': 'subscriptions',
  'transfer': 'transfer',
  'debt': 'debt',
  'entertainment': 'entertainment',
  'health': 'health',
  'education': 'education',
  'personal': 'personal',
  'gifts': 'gifts',
  'vacation': 'vacation',
  'business': 'business',
  'business meetings': 'business_meetings',
  'fuel (etims)': 'fuel_etims',
  'other business': 'other_business',
  'other': 'other',
};
